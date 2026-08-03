#!/usr/bin/env bash
# azdo-mine.sh - safe Azure DevOps (Azure Boards) helper scoped to the current user.
#
# Every operation is confined to the authenticated user's own work items on the
# expected account:
#   * Reads are filtered to [System.AssignedTo] = @Me.
#   * Mutations are refused unless the target item is assigned to @Me
#     (checked with a server-side WIQL join, never by comparing name strings).
#   * The acting Azure DevOps identity is verified via connectionData, not
#     `az account show` (the ARM identity can diverge from the Boards identity).
#   * A personal access token env var, or an unset expected account, fails closed.
#   * Only explicitly requested fields are written: no hours, state, or other
#     value is invented on the caller's behalf.
#   * A closed work item is read-only until the user has been asked what to do
#     with it (--allow-closed records that they answered).
#   * Missing tooling is reported, never installed behind the user's back.
#   * Deletion is never supported.
#
# See SKILL.md for setup and usage.

set -euo pipefail

# Azure DevOps AAD resource id (used to acquire a Boards-scoped token via az rest).
AZDO_RESOURCE="499b84ac-1321-427f-aa17-267ca6975798"
COMPLETED_WORK_FIELD="Microsoft.VSTS.Scheduling.CompletedWork"

die()  { echo "azdo-mine: refused: $*" >&2; exit 1; }
note() { echo "azdo-mine: $*" >&2; }
lc()   { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# --- org / project resolution ------------------------------------------------
# Prefer explicit env overrides; otherwise parse the Azure DevOps git remote.
resolve_org_project() {
  ORG="${AZDO_ORG_URL:-}"
  PROJECT="${AZDO_PROJECT:-}"
  if [[ -n "$ORG" && -n "$PROJECT" ]]; then
    return
  fi
  local remote
  remote="$(git remote get-url origin 2>/dev/null || true)"
  [[ -n "$remote" ]] || die "cannot resolve org/project: set AZDO_ORG_URL and AZDO_PROJECT, or run inside the Azure DevOps repo"
  # Match dev.azure.com/<org>/<project>/_git/<repo>, ignoring any userinfo prefix
  # such as 'myorg@' that appears before the host.
  if [[ "$remote" =~ dev\.azure\.com/([^/]+)/([^/]+)/_git/ ]]; then
    ORG="${ORG:-https://dev.azure.com/${BASH_REMATCH[1]}}"
    PROJECT="${PROJECT:-${BASH_REMATCH[2]}}"
  else
    die "cannot parse org/project from remote '$remote'; set AZDO_ORG_URL and AZDO_PROJECT"
  fi
}

# --- identity guards ---------------------------------------------------------
verify_identity() {
  # 1) A PAT would make every Boards op act as the token owner regardless of who
  #    is logged in, silently defeating the account check. Fail closed.
  if [[ -n "${AZURE_DEVOPS_EXT_PAT:-}" || -n "${AZDO_PERSONAL_ACCESS_TOKEN:-}" ]]; then
    die "a personal access token env var is set (AZURE_DEVOPS_EXT_PAT / AZDO_PERSONAL_ACCESS_TOKEN); unset it so operations run as your logged-in identity"
  fi
  # 2) The expected account must be configured explicitly. Never fall back to
  #    "whatever is logged in".
  local expected="${AZDO_EXPECTED_ACCOUNT:-}"
  [[ -n "$expected" ]] || die "AZDO_EXPECTED_ACCOUNT is not set; export it to your account email so operations only ever run as you"
  # 3) Determine the identity that actually performs Boards operations.
  ACTING_EMAIL="$(az rest --resource "$AZDO_RESOURCE" \
      --url "${ORG}/_apis/connectionData?api-version=7.1-preview" \
      --query 'authenticatedUser.properties.Account."$value"' -o tsv 2>/dev/null || true)"
  [[ -n "$ACTING_EMAIL" ]] || die "could not determine the acting Azure DevOps identity; are you logged in? try 'az login'"
  # 4) Refuse unless the acting identity is exactly the expected account.
  if [[ "$(lc "$ACTING_EMAIL")" != "$(lc "$expected")" ]]; then
    die "acting identity '$ACTING_EMAIL' does not match AZDO_EXPECTED_ACCOUNT '$expected'"
  fi
}

# --- ownership guard ---------------------------------------------------------
# Server-side join: an item counts as "mine" only if it is returned by a query
# that filters on both its id and [System.AssignedTo] = @Me.
assert_mine() {
  local id="$1"
  local hit
  hit="$(az boards query --org "$ORG" --project "$PROJECT" \
      --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.Id] = ${id} AND [System.AssignedTo] = @Me" \
      --query "[0].id" -o tsv 2>/dev/null || true)"
  [[ "$hit" == "$id" ]] || die "work item ${id} is not assigned to you; refusing to touch it"
}

# --- state guard -------------------------------------------------------------
# A closed item is off limits until a human has decided what to do with it. The
# decision uses the state *category* from the process template, not a hardcoded
# list of state names: names are per-process configuration this repo cannot know.
ITEM_TYPE=""; ITEM_STATE=""; ITEM_AREA=""; ITEM_ITER=""

read_item() {
  local id="$1" row
  # The outer brackets are load-bearing: -o tsv prints one *row* per top-level
  # list element and only tab-joins within a row. A flat [a,b,c,d] therefore
  # comes back as four lines with no tab anywhere, and the single `read` below
  # would swallow line one whole and leave the rest empty. [[a,b,c,d]] is one
  # row of four columns, which is what `read` is parsing.
  # tr -d '\r' is for non-MSYS shells: MSYS bash strips the trailing CRLF in
  # $(...) but keeps the interior ones, and elsewhere even the trailing \r stays.
  row="$(az boards work-item show --id "$id" --org "$ORG" \
      --query "[[fields.\"System.WorkItemType\",fields.\"System.State\",fields.\"System.AreaPath\",fields.\"System.IterationPath\"]]" -o tsv | tr -d '\r')"
  IFS=$'\t' read -r ITEM_TYPE ITEM_STATE ITEM_AREA ITEM_ITER <<<"$row"
  [[ -n "$ITEM_TYPE" && -n "$ITEM_STATE" ]] || die "could not read the type and state of work item ${id} (checked with 'az boards work-item show --id ${id}')"
}

assert_not_closed() {
  local id="$1" approved="$2" category
  read_item "$id"
  category="$(az rest --resource "$AZDO_RESOURCE" \
      --url "${ORG}/${PROJECT}/_apis/wit/workitemtypes/${ITEM_TYPE// /%20}/states?api-version=7.1" \
      --query "value[?name=='${ITEM_STATE}'].category | [0]" -o tsv 2>/dev/null || true)"
  [[ -n "$category" ]] || die "cannot tell whether '${ITEM_STATE}' is a closed state for ${ITEM_TYPE} ${id}; stopping instead of guessing - ask the user how to proceed"
  case "$category" in
    Completed|Removed)
      [[ "$approved" == "approved" ]] || die "work item ${id} is '${ITEM_STATE}' (state category ${category}); stop and ask the user what to do with a closed item, then pass --allow-closed once they have answered"
      note "work item ${id} is '${ITEM_STATE}'; proceeding because --allow-closed was passed"
      ;;
  esac
}

# --- dependency guard --------------------------------------------------------
# Report what is missing and why, then stop. Installing anything is the user's
# call, made through 'install-deps' after they have agreed to it.
require_deps() {
  command -v az >/dev/null 2>&1 \
    || die "the Azure CLI (\"az\") is not installed; it is what talks to Azure Boards. Tell the user it is needed and let them install it (https://aka.ms/installazurecli) - this script never installs it"
  # An az configured to add extensions on its own would install software nobody
  # approved, which is the decision this guard hands back to the user.
  local dynamic="${AZURE_EXTENSION_USE_DYNAMIC_INSTALL:-}"
  [[ -n "$dynamic" ]] || dynamic="$(az config get extension.use_dynamic_install --query value -o tsv 2>/dev/null || true)"
  if [[ "$(lc "$dynamic")" == "yes_without_prompt" ]]; then
    die "az is set to install extensions without prompting (extension.use_dynamic_install=yes_without_prompt); ask the user to set it to 'yes_prompt' so nothing is installed unasked"
  fi
  az extension show --name azure-devops -o none 2>/dev/null \
    || die "the \"azure-devops\" az extension is missing; it provides the 'az boards' commands this script runs. Tell the user what it is and why it is needed, and run 'azdo-mine.sh install-deps' only after they agree"
}

preflight() { require_deps; resolve_org_project; verify_identity; }

# --- subcommands -------------------------------------------------------------
cmd_whoami() {
  preflight
  echo "Account:      $ACTING_EMAIL"
  echo "Organization: $ORG"
  echo "Project:      $PROJECT"
}

cmd_list() {
  preflight
  local state_filter="AND [System.State] NOT IN ('Closed','Removed','Done')"
  [[ "${1:-}" == "--all-states" ]] && state_filter=""
  az boards query --org "$ORG" --project "$PROJECT" \
    --wiql "SELECT [System.Id],[System.WorkItemType],[System.Title],[System.State] FROM WorkItems WHERE [System.AssignedTo] = @Me ${state_filter} ORDER BY [System.ChangedDate] DESC" \
    --query "[].{ID:fields.\"System.Id\",Type:fields.\"System.WorkItemType\",State:fields.\"System.State\",Title:fields.\"System.Title\"}" -o table
}

cmd_show() {
  local id="${1:?usage: show <id>}"
  preflight; assert_mine "$id"
  az boards work-item show --id "$id" --org "$ORG" \
    --query "{ID:id,Type:fields.\"System.WorkItemType\",State:fields.\"System.State\",Assigned:fields.\"System.AssignedTo\".uniqueName,Parent:fields.\"System.Parent\",Title:fields.\"System.Title\"}" -o json
}

cmd_children() {
  local id="${1:?usage: children <parent-id>}"
  preflight; assert_mine "$id"
  az boards query --org "$ORG" --project "$PROJECT" \
    --wiql "SELECT [System.Id],[System.WorkItemType],[System.Title],[System.State] FROM WorkItems WHERE [System.Parent] = ${id} ORDER BY [System.Id] ASC" \
    --query "[].{ID:fields.\"System.Id\",Type:fields.\"System.WorkItemType\",State:fields.\"System.State\",Title:fields.\"System.Title\"}" -o table
}

cmd_create_task() {
  local usage="usage: create-task <parent-id> <title> [--completed-work N] [--state STATE] [--allow-closed]"
  local parent="${1:?$usage}"; shift
  local title="${1:?$usage}"; shift
  # Empty means "the caller did not ask for it", so the field is left alone.
  # There are deliberately no defaults here: a value nobody requested is a value
  # nobody can verify.
  local completed_work="" state="" approved=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --completed-work) completed_work="${2:?--completed-work needs a value}"; shift 2 ;;
      --state) state="${2:?--state needs a value}"; shift 2 ;;
      --allow-closed) approved="approved"; shift ;;
      *) die "create-task: unknown option '$1' ($usage)" ;;
    esac
  done
  if [[ -n "$completed_work" && ! "$completed_work" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    die "create-task: --completed-work must be a number of hours, got '$completed_work'"
  fi
  # Adding a child changes the parent's relations, so a closed parent is guarded
  # exactly like any other closed item.
  preflight; assert_mine "$parent"; assert_not_closed "$parent" "$approved"
  # Only pass --fields when hours were actually requested.
  local fields=()
  [[ -n "$completed_work" ]] && fields=(--fields "${COMPLETED_WORK_FIELD}=${completed_work}")
  # Create the task (starts in 'New'), assigned to the acting identity, in the
  # parent's area and iteration.
  local new_id
  new_id="$(az boards work-item create --org "$ORG" --project "$PROJECT" \
    --type "Task" --title "$title" --assigned-to "$ACTING_EMAIL" \
    --area "$ITEM_AREA" --iteration "$ITEM_ITER" \
    ${fields[@]+"${fields[@]}"} --query "id" -o tsv)"
  az boards work-item relation add --id "$new_id" --org "$ORG" \
    --relation-type "parent" --target-id "$parent" -o none
  # A new item always starts in 'New'; move it only if a state was requested.
  if [[ -n "$state" ]]; then
    az boards work-item update --id "$new_id" --org "$ORG" --state "$state" -o none
  fi
  # Report the exact field set, so an unrequested value cannot pass unnoticed.
  echo "Created Task ${new_id} under ${parent}"
  echo "  title              = ${title}"
  echo "  assigned           = ${ACTING_EMAIL}"
  echo "  area / iteration   = inherited from ${parent}"
  echo "  state              = ${state:-New (not requested)}"
  echo "  ${COMPLETED_WORK_FIELD} = ${completed_work:-(not set)}"
}

cmd_update() {
  local usage="usage: update <id> [--title TEXT] [--state STATE] [--completed-work N] [--allow-closed]"
  local id="${1:?$usage}"; shift
  # Same rule as create-task: an empty variable means the caller never named that
  # field, and a field nobody named is never sent.
  local title="" state="" completed_work="" approved=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="${2:?--title needs a value}"; shift 2 ;;
      --state) state="${2:?--state needs a value}"; shift 2 ;;
      --completed-work) completed_work="${2:?--completed-work needs a value}"; shift 2 ;;
      --allow-closed) approved="approved"; shift ;;
      *) die "update: unknown option '$1' ($usage)" ;;
    esac
  done
  [[ -n "$title$state$completed_work" ]] \
    || die "update: nothing to update; name at least one field the user asked to change ($usage)"
  if [[ -n "$completed_work" && ! "$completed_work" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    die "update: --completed-work must be a number of hours, got '$completed_work'"
  fi
  preflight; assert_mine "$id"; assert_not_closed "$id" "$approved"
  local args=(--id "$id" --org "$ORG")
  [[ -n "$title" ]] && args+=(--title "$title")
  [[ -n "$state" ]] && args+=(--state "$state")
  [[ -n "$completed_work" ]] && args+=(--fields "${COMPLETED_WORK_FIELD}=${completed_work}")
  az boards work-item update "${args[@]}" -o none
  # Report the change, including the state it moved away from.
  echo "Updated work item ${id} (${ITEM_TYPE})"
  [[ -n "$title" ]] && echo "  title              = ${title}"
  [[ -n "$state" ]] && echo "  state              = ${ITEM_STATE} -> ${state}"
  [[ -n "$completed_work" ]] && echo "  ${COMPLETED_WORK_FIELD} = ${completed_work}"
  echo "  fields not touched by this call are unchanged"
}

cmd_set_state() {
  local usage="usage: set-state <id> <state> [--allow-closed]"
  local id="${1:?$usage}"; shift
  local state="${1:?$usage}"; shift
  cmd_update "$id" --state "$state" "$@"
}

cmd_comment() {
  local usage="usage: comment <id> <text> [--allow-closed]"
  local id="${1:?$usage}"; shift
  local text="${1:?$usage}"; shift
  local approved=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --allow-closed) approved="approved"; shift ;;
      *) die "comment: unexpected argument '$1'; pass the comment as ONE quoted argument so it is posted exactly as written ($usage)" ;;
    esac
  done
  preflight; assert_mine "$id"; assert_not_closed "$id" "$approved"
  az boards work-item update --id "$id" --org "$ORG" --discussion "$text" -o none
  echo "Comment added to ${id} - everyone watching the item is notified"
}

cmd_install_deps() {
  command -v az >/dev/null 2>&1 \
    || die "the Azure CLI (\"az\") is not installed; installing it is the user's own step (https://aka.ms/installazurecli)"
  note "installing the 'azure-devops' az extension - nothing else"
  az extension add --name azure-devops -o none
  echo "Installed: azure-devops az extension"
}

usage() {
  cat <<'EOF'
azdo-mine.sh - safe Azure DevOps work-item helper scoped to your own items.

Setup (once per shell):
  export AZDO_EXPECTED_ACCOUNT="you@example.com"   # required; fails closed if unset
  # optional overrides (otherwise parsed from the git remote):
  export AZDO_ORG_URL="https://dev.azure.com/<org>"
  export AZDO_PROJECT="<project>"

Commands:
  whoami                                 Show the verified acting account, org, project
  list [--all-states]                    List work items assigned to you
  show <id>                              Show one of your work items
  children <parent-id>                   List children of one of your items
  create-task <parent-id> <title> [--completed-work N] [--state STATE]
                                         Create a Task under your item, assigned to you.
                                         Sets nothing else: omit a flag and that field
                                         is left untouched (state stays 'New', no hours).
  update <id> [--title TEXT] [--state STATE] [--completed-work N]
                                         Change fields on one of your items. Only the
                                         flags you pass are sent; everything else on the
                                         item is left exactly as it was.
  set-state <id> <state>                 Change the state of one of your items
  comment <id> <text>                    Add a discussion comment (text must be ONE
                                         quoted argument; watchers get notified)
  install-deps                           Install the azure-devops az extension. Run this
                                         only after the user has agreed to it.

Every mutating command adds [--allow-closed], which is refused-by-default: a closed
work item is read-only until you have asked the user what to do with it.

Pass only values the requester actually gave you. Deletion is intentionally not
supported.
EOF
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    whoami|check)   cmd_whoami "$@" ;;
    list)           cmd_list "$@" ;;
    show)           cmd_show "$@" ;;
    children)       cmd_children "$@" ;;
    create-task)    cmd_create_task "$@" ;;
    update)         cmd_update "$@" ;;
    set-state)      cmd_set_state "$@" ;;
    comment)        cmd_comment "$@" ;;
    install-deps)   cmd_install_deps "$@" ;;
    delete|remove)  die "deletion is not supported by this helper" ;;
    ""|-h|--help|help) usage ;;
    *)              die "unknown command '$cmd' (run: azdo-mine.sh help)" ;;
  esac
}

main "$@"
