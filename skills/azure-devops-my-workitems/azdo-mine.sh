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

preflight() { resolve_org_project; verify_identity; }

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
  local parent="${1:?usage: create-task <parent-id> <title> [--hours N] [--state STATE]}"; shift
  local title="${1:?usage: create-task <parent-id> <title> [--hours N] [--state STATE]}"; shift
  local hours=1 state="Active"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hours) hours="${2:?--hours needs a value}"; shift 2 ;;
      --state) state="${2:?--state needs a value}"; shift 2 ;;
      *) die "create-task: unknown option '$1'" ;;
    esac
  done
  preflight; assert_mine "$parent"
  # Land the task with its parent by inheriting area and iteration.
  local area iter
  area="$(az boards work-item show --id "$parent" --org "$ORG" --query 'fields."System.AreaPath"' -o tsv)"
  iter="$(az boards work-item show --id "$parent" --org "$ORG" --query 'fields."System.IterationPath"' -o tsv)"
  # Create the task (starts in 'New'), assigned to the acting identity.
  local new_id
  new_id="$(az boards work-item create --org "$ORG" --project "$PROJECT" \
    --type "Task" --title "$title" --assigned-to "$ACTING_EMAIL" \
    --area "$area" --iteration "$iter" \
    --fields "${COMPLETED_WORK_FIELD}=${hours}" --query "id" -o tsv)"
  az boards work-item relation add --id "$new_id" --org "$ORG" \
    --relation-type "parent" --target-id "$parent" -o none
  # 'New' -> target state cannot be set at creation time, so update afterwards.
  if [[ "$state" != "New" ]]; then
    az boards work-item update --id "$new_id" --org "$ORG" --state "$state" -o none
  fi
  echo "Created Task ${new_id} under ${parent}: ${title} (state=${state}, ${COMPLETED_WORK_FIELD}=${hours}, assigned=${ACTING_EMAIL})"
}

cmd_set_state() {
  local id="${1:?usage: set-state <id> <state>}"
  local state="${2:?usage: set-state <id> <state>}"
  preflight; assert_mine "$id"
  az boards work-item update --id "$id" --org "$ORG" --state "$state" \
    --query "fields.\"System.State\"" -o tsv
}

cmd_comment() {
  local id="${1:?usage: comment <id> <text>}"; shift
  local text="$*"
  [[ -n "$text" ]] || die "comment text is empty"
  preflight; assert_mine "$id"
  az boards work-item update --id "$id" --org "$ORG" --discussion "$text" -o none
  echo "Comment added to ${id}"
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
  create-task <parent-id> <title> [--hours N] [--state STATE]
                                         Create a Task under your item, assigned to you
                                         (default: --hours 1 --state Active)
  set-state <id> <state>                 Change the state of one of your items
  comment <id> <text>                    Add a discussion comment to one of your items

Deletion is intentionally not supported.
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
    set-state)      cmd_set_state "$@" ;;
    comment)        cmd_comment "$@" ;;
    delete|remove)  die "deletion is not supported by this helper" ;;
    ""|-h|--help|help) usage ;;
    *)              die "unknown command '$cmd' (run: azdo-mine.sh help)" ;;
  esac
}

main "$@"
