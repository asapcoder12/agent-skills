#!/usr/bin/env bash
# test-azdo-mine.sh - offline tests for what azdo-mine.sh actually sends to Azure.
#
# `az` is stubbed on PATH and every invocation is logged, so the tests assert on
# the exact set of fields the script sets - without creating or touching a real
# work item. Three properties are under test:
#   * literal requests: only fields the caller named are ever sent;
#   * closed items: mutations refuse until the user has been asked;
#   * dependencies: nothing is installed unless install-deps is run explicitly.
#
# Run: ./test-azdo-mine.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/azdo-mine.sh"
ORIG_PATH="$PATH"
FAILURES=0
CURRENT=""

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n        %s\n' "$1" "$2"; FAILURES=$((FAILURES + 1)); }

# --- stubbed environment -----------------------------------------------------
# Stub behaviour is driven by STUB_* env vars so each test can shape the fake
# Azure responses it needs (closed state, missing extension, and so on).
setup() {
  CURRENT="$1"
  WORK="$(mktemp -d)"
  export AZ_LOG="$WORK/az.log"
  : >"$AZ_LOG"
  cat >"$WORK/az" <<'STUB'
#!/usr/bin/env bash
# Minimal `az` stand-in: log the call, then answer just enough to keep going.
printf '%s\n' "$*" >>"$AZ_LOG"
args="$*"
case "$args" in
  *connectionData*)
    echo "$AZDO_EXPECTED_ACCOUNT" ;;
  *"/states?api-version"*)
    # State category lookup; empty output simulates a failed lookup.
    printf '%s' "${STUB_CATEGORY-InProgress}"; echo ;;
  "boards query"*)
    # assert_mine: echo back the id it asked about, i.e. "the item is yours".
    printf '%s' "$args" | sed -n 's/.*\[System\.Id\] = \([0-9]*\).*/\1/p' ;;
  *"work-item show"*)
    printf '%s\t%s\tProj\\Area\tProj\\Iter\n' "${STUB_TYPE:-Task}" "${STUB_STATE:-Active}" ;;
  *"work-item create"*)
    echo 999 ;;
  *"extension show"*)
    [[ -n "${STUB_NO_EXT:-}" ]] && exit 1 ;;
  *"config get"*)
    echo "${STUB_DYNAMIC:-yes_prompt}" ;;
esac
exit 0
STUB
  chmod +x "$WORK/az"
  export PATH="$WORK:$PATH"
  export AZDO_EXPECTED_ACCOUNT="me@example.com"
  export AZDO_ORG_URL="https://dev.azure.com/org"
  export AZDO_PROJECT="proj"
  unset AZURE_DEVOPS_EXT_PAT AZDO_PERSONAL_ACCESS_TOKEN
  unset STUB_CATEGORY STUB_STATE STUB_TYPE STUB_NO_EXT STUB_DYNAMIC
  unset AZURE_EXTENSION_USE_DYNAMIC_INSTALL
  # Fail closed: if the stub is not the `az` being called, a test could hit the
  # real Azure DevOps. Never run a case until the stub is proven to be in front.
  local resolved
  resolved="$(command -v az || true)"
  [[ "$resolved" == "$WORK/az" ]] || {
    printf 'ABORT  stub az is not first on PATH (got %s)\n' "${resolved:-none}"
    exit 2
  }
}

teardown() {
  PATH="$ORIG_PATH"
  rm -rf "$WORK"
}

run() { bash "$SCRIPT" "$@" >"$WORK/out" 2>"$WORK/err"; echo $?; }

# --- assertions --------------------------------------------------------------
log_has() {
  grep -qF -- "$1" "$AZ_LOG" \
    && pass "$CURRENT: sends '$1'" \
    || fail "$CURRENT: expected '$1' in the az calls" "$(cat "$AZ_LOG")"
}

log_lacks() {
  grep -qF -- "$1" "$AZ_LOG" \
    && fail "$CURRENT: must not send '$1'" "$(grep -F -- "$1" "$AZ_LOG")" \
    || pass "$CURRENT: never sends '$1'"
}

out_has() {
  grep -qF -- "$1" "$WORK/out" \
    && pass "$CURRENT: reports '$1'" \
    || fail "$CURRENT: expected '$1' on stdout" "$(cat "$WORK/out")"
}

refused() {
  local status="$1" needle="$2"
  if [[ "$status" != "0" ]] && grep -qF -- "$needle" "$WORK/err"; then
    pass "$CURRENT: refused ('$needle')"
  else
    fail "$CURRENT: expected refusal mentioning '$needle'" "status=$status err=$(cat "$WORK/err")"
  fi
}

# --- create-task: only what was asked ----------------------------------------
setup "create-task without flags"
run create-task 30769 "Migrate token to SecretStr" >/dev/null
log_has "--title Migrate token to SecretStr"
log_has "--assigned-to me@example.com"
log_has '--area Proj\Area'
log_has '--iteration Proj\Iter'
log_has "relation add --id 999 --org https://dev.azure.com/org --relation-type parent --target-id 30769"
log_lacks "CompletedWork"
log_lacks "work-item update"
teardown

setup "create-task with explicit values"
run create-task 30769 "T" --completed-work 3 --state Active >/dev/null
log_has "Microsoft.VSTS.Scheduling.CompletedWork=3"
log_has "--state Active"
teardown

# The old ambiguous --hours flag has to fail loudly: "hours" does not name a
# field, and guessing one is exactly the invention this guard exists to stop.
setup "legacy --hours flag"
status="$(run create-task 30769 "T" --hours 1)"
refused "$status" "unknown option"
log_lacks "work-item create"
teardown

setup "non-numeric completed work"
status="$(run create-task 30769 "T" --completed-work soon)"
refused "$status" "must be a number of hours"
log_lacks "work-item create"
teardown

setup "empty title"
status="$(run create-task 30769 "")"
refused "$status" "usage: create-task"
log_lacks "work-item create"
teardown

# --- update: only what was asked ---------------------------------------------
setup "update one field"
run update 30769 --title "Renamed by request" >/dev/null
log_has "work-item update --id 30769"
log_has "--title Renamed by request"
log_lacks "--state"
log_lacks "CompletedWork"
out_has "fields not touched by this call are unchanged"
teardown

setup "update with no fields"
status="$(run update 30769)"
refused "$status" "nothing to update"
log_lacks "work-item update"
teardown

setup "update with unknown option"
status="$(run update 30769 --priority 1)"
refused "$status" "unknown option"
log_lacks "work-item update"
teardown

setup "update with non-numeric hours"
status="$(run update 30769 --completed-work later)"
refused "$status" "must be a number of hours"
log_lacks "work-item update"
teardown

# set-state routes through update, so the previous state is visible.
setup "set-state shows the previous state"
run set-state 30769 Resolved >/dev/null
log_has "--state Resolved"
out_has "Active -> Resolved"
teardown

# --- closed items: stop and ask ----------------------------------------------
setup "update a closed item"
export STUB_STATE="Closed" STUB_CATEGORY="Completed"
status="$(run update 30769 --title "X")"
refused "$status" "ask the user what to do with a closed item"
log_lacks "work-item update --id"
teardown

setup "update a closed item after approval"
export STUB_STATE="Closed" STUB_CATEGORY="Completed"
run update 30769 --title "X" --allow-closed >/dev/null
log_has "--title X"
teardown

setup "comment on a closed item"
export STUB_STATE="Done" STUB_CATEGORY="Completed"
status="$(run comment 30769 "ping")"
refused "$status" "ask the user what to do with a closed item"
log_lacks "--discussion"
teardown

setup "create-task under a closed parent"
export STUB_STATE="Removed" STUB_CATEGORY="Removed"
status="$(run create-task 30769 "T")"
refused "$status" "ask the user what to do with a closed item"
log_lacks "work-item create"
teardown

# An unresolvable state category must stop, not fall back to guessing by name.
setup "unknown state category"
export STUB_CATEGORY=""
status="$(run update 30769 --title "X")"
refused "$status" "stopping instead of guessing"
log_lacks "work-item update --id"
teardown

# The comment text must arrive as one argument, or whitespace is silently
# reflowed and the posted text is no longer what the user wrote.
setup "comment split across arguments"
status="$(run comment 30769 ping the reviewer)"
refused "$status" "ONE quoted argument"
log_lacks "--discussion"
teardown

# --- dependencies: report, never install silently -----------------------------
setup "azure cli missing"
PATH="/usr/bin"
status="$(run list)"
refused "$status" 'Azure CLI ("az") is not installed'
teardown

setup "azure-devops extension missing"
export STUB_NO_EXT=1
status="$(run list)"
refused "$status" '"azure-devops" az extension is missing'
log_lacks "extension add"
teardown

setup "az configured to install extensions silently"
export STUB_DYNAMIC="yes_without_prompt"
status="$(run list)"
refused "$status" "without prompting"
log_lacks "extension add"
teardown

setup "install-deps installs only the extension"
run install-deps >/dev/null
log_has "extension add --name azure-devops"
log_lacks "work-item"
teardown

printf '\n%s\n' "$([[ "$FAILURES" -eq 0 ]] && echo "all tests passed" || echo "$FAILURES check(s) failed")"
exit $((FAILURES > 0))
