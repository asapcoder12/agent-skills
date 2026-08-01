---
name: azure-devops-my-workitems
description: Use ONLY when the user explicitly asks about their own Azure DevOps / Azure Boards work items, or invokes this skill by name. Explicit triggers - "my work items", "list tasks under story N", "add a task to work item N", "set item N to Active/Resolved", "comment on work item N". Do NOT auto-trigger from general git, repo, PR, or build activity, or from any task where the user has not clearly mentioned work items / Azure Boards. Scope is strictly the user's own account and items assigned to them. Keywords - az boards, azure-devops CLI, work item, AssignedTo, @Me.
---

# Azure DevOps: my work items only

## Overview

Manage your own Azure Boards work items from the CLI without ever touching
someone else's item or acting as the wrong identity. **Core principle: route
every operation through `azdo-mine.sh`, never raw `az boards ... update/create`.**
The script fails closed - if it cannot prove the operation is safe, it refuses.

## When to use

- Listing the work items assigned to you.
- Creating a Task under one of your items (auto-assigned to you).
- Changing the state of, or commenting on, an item assigned to you.
- Any Azure Boards work where the hard requirement is "only my account, only my
  items".

Not for: bulk board administration, editing other people's items, or deletion
(unsupported by design).

## Setup (once per shell)

```bash
az login                                          # if not already authenticated
export AZDO_EXPECTED_ACCOUNT="you@example.com"    # REQUIRED; unset => refuse
# Optional (otherwise parsed from the git remote):
# export AZDO_ORG_URL="https://dev.azure.com/<org>"
# export AZDO_PROJECT="<project>"
```

The `azure-devops` extension is needed once: `az extension add --name azure-devops`.

## Quick reference

Run from the repo (org/project are parsed from the git remote unless overridden).

| Command | Does |
|---|---|
| `azdo-mine.sh whoami` | Print the verified acting account, org, project |
| `azdo-mine.sh list [--all-states]` | Work items assigned to you |
| `azdo-mine.sh show <id>` | Show one of your items |
| `azdo-mine.sh children <parent-id>` | Children of one of your items |
| `azdo-mine.sh create-task <parent-id> <title> [--hours N] [--state STATE]` | New Task under your item, assigned to you (default `--hours 1 --state Active`) |
| `azdo-mine.sh set-state <id> <state>` | Change the state of your item |
| `azdo-mine.sh comment <id> <text>` | Add a discussion comment to your item |

## What the guard enforces

- **Right identity, not `az account show`.** The acting Boards identity is read
  from `connectionData.authenticatedUser` (the token that actually performs
  writes) and must equal `AZDO_EXPECTED_ACCOUNT`.
- **No PAT override.** If `AZURE_DEVOPS_EXT_PAT` / `AZDO_PERSONAL_ACCESS_TOKEN`
  is set, it refuses - a PAT would act as its owner and bypass the account check.
- **Ownership by server-side join.** Before any mutation it runs
  `WHERE [System.Id] = <id> AND [System.AssignedTo] = @Me`; an empty result means
  "not mine" and it refuses. It never string-compares display names / emails.
- **Fail closed.** Unset expected account, unresolvable identity, or unparseable
  org/project all refuse rather than guess.
- **No deletion.**

## Example (the common flow)

```bash
export AZDO_EXPECTED_ACCOUNT="you@example.com"
azdo-mine.sh whoami                                   # confirm you are you
azdo-mine.sh list                                     # your open items
azdo-mine.sh create-task 30769 "Migrate token to SecretStr"   # Active, 1h, yours
azdo-mine.sh children 30769                           # verify it landed
azdo-mine.sh set-state 30775 "Resolved"               # only if 30775 is yours
```

## Common mistakes

- **Calling raw `az boards work-item update/create` directly.** That skips every
  guard - it will happily edit an item that is not yours or act as the wrong
  identity. Route through `azdo-mine.sh`.
- **Trusting `az account show` for identity.** It is the ARM identity and can
  differ from the Boards identity (and a PAT ignores it entirely).
- **Expecting `--state Active` at creation.** A new work item starts in `New`;
  the state is set by a follow-up update (the script does this for you).
- **Passing `@Me` to `--assigned-to`.** `@Me` is a WIQL macro, not an assignment
  value; the script assigns the resolved account email.

## Red flags - stop and use the guard

- About to type `az boards work-item update --id ...` by hand.
- About to modify an item without knowing whether it is assigned to you.
- Reaching for a PAT to "make auth simpler".

All of these mean: run the operation through `azdo-mine.sh`.
