---
name: azure-devops-my-workitems
description: Use ONLY when the user explicitly asks about their own Azure DevOps / Azure Boards work items, or invokes this skill by name. Triggers - "my work items", "list tasks under story N", "add a task to work item N", "rename/update item N", "put N hours on item N", "set item N to Active/Resolved", "comment on work item N". Do NOT auto-trigger from git, branch, PR, or build activity - a branch, commit, or PR carrying a work-item id (feature/30856/..., US 30472, AB#30769) is not a request to read or change that item, and finishing a coding task is not a request to update its board. Scope - only items assigned to the user, never anyone else's. Keywords - az boards, azure-devops CLI, work item, AssignedTo, @Me.
---

# Azure DevOps: my work items only

## Overview

Manage your own Azure Boards work items from the CLI without ever touching
someone else's item or acting as the wrong identity. **Core principle: route
every operation through `azdo-mine.sh`, never raw `az boards ... update/create`.**
The script fails closed - if it cannot prove the operation is safe, it refuses.

**Second core principle: a write carries only the values the requester named.**
Every field on a work item is read by people who assume a human put it there.

## Create only what was asked

**The requester's words are the whole spec. Every field you send must trace back
to something they actually said.**

- Send `--completed-work` / `--state` / `--title` **only** when the request named
  that value. Omit the flag and the field stays untouched - a new Task simply
  stays in `New` with no hours on it. That is a correct outcome, not an
  incomplete one.
- This applies identically to `update` on an existing item: it changes exactly
  the flags you pass and leaves every other field as it was. Editing one field is
  never an invitation to "finish" the others.
- Pass the title **verbatim**. No rewording, no prefix, no work-item id, no
  capitalisation fix, no "clearer" phrasing.
- Comment text goes in verbatim too - no added signature, summary, or context.
- `--completed-work` writes `Microsoft.VSTS.Scheduling.CompletedWork` (hours
  already spent). "3 hours" in a request does not say which hours field it means;
  that is a question to ask, not a mapping to pick.

**No exceptions:**

- Not "1 hour is a harmless placeholder".
- Not "Active is obviously what they meant by 'add a task'".
- Not "the board convention is to always fill X".
- Not "I'll set it and they can correct it later" - an invented value is worse
  than an empty field, because nobody re-reviews a field that looks filled in.

### If the request does not name a value, ask

Ask first, create after. One question covering every field the request left
unnamed, then send exactly what comes back:

> Creating "Migrate token to SecretStr" as a Task under 30769. Hours
> (`CompletedWork`) - none, or a number? State - leave it `New`, or set one?

"None" / "leave it" means omit the flag. Never resolve the question yourself, and
never resolve it by looking at the parent item, sibling tasks, or team habit -
reading a number off a neighbour is still inventing it for this item.

### Report the field set afterwards

`create-task` prints every field it set, including `state = New (not requested)`
and `CompletedWork = (not set)`. Show that output verbatim - it is the
requester's only chance to spot a value they never asked for.

### Rationalizations

| Excuse | Reality |
|---|---|
| "Hours are mandatory, the board needs a number" | Optional in Azure DevOps. With no `--completed-work`, no `--fields` argument is sent at all, and creation succeeds. |
| "1 hour is a safe default" | It is a fabricated time entry on a real board that somebody reports on. |
| "They said 'add a task' - tasks start Active here" | They said add a task. A new task is `New`. |
| "The title reads better tidied up" | Their wording is theirs and is what they will search for. Copy it byte for byte. |
| "The parent is 3h, so the child should be too" | Inheriting a number is inventing a number. |
| "Asking is annoying over something this small" | One question costs a line of chat. A wrong field costs a board correction nobody knows to make. |
| "While updating the title I may as well fix the hours" | Two changes were asked for zero times. `update` sends one flag per named field. |
| "The item is Closed but this edit is tiny" | Closed means the work is accounted for. Any edit is a decision the user makes, not you. |
| "Installing an extension is harmless" | It is software on their machine. Name it, say why, wait for yes. |

## Closed items are read-only until the user decides

**A work item whose state category is `Completed` or `Removed` is off limits.
Stop, tell the user, ask what to do - do not act.**

`update`, `set-state`, `comment`, and `create-task` (on a closed *parent*) all
refuse on a closed item and say so. That refusal is the signal to go back to the
user, not a hurdle to route around:

> 30775 is `Closed` (category `Completed`). Editing a closed item changes work
> that is already reported on. Do you want me to change it anyway, reopen it
> first, or leave it and create a new item?

Only after they answer, and only if they said go ahead, pass `--allow-closed` -
one flag, on the one command they approved. It is not a setting to keep using for
the rest of the session.

- Reading is always fine: `list`, `show`, and `children` work on closed items and
  need no approval. Show them when asked.
- Closedness is decided by the **state category** from the process template, not
  a name this repo guessed - so `Done`, `Removed`, and a custom terminal state
  are all caught.
- If the category cannot be resolved, the script refuses rather than assume the
  item is open. Report that too; do not retry your way past it.

## First run: report what is missing, then ask

**Never install anything on the user's machine without telling them what and why,
and getting a yes.**

`preflight` refuses when the Azure CLI is absent, when the `azure-devops`
extension is absent, or when `az` is configured to install extensions without
prompting (`extension.use_dynamic_install=yes_without_prompt`). On any of those:
stop and report in plain terms - what is missing, what it is for, what installing
it involves - and wait.

> `az boards` needs the `azure-devops` CLI extension, which is not installed. It
> is a Microsoft extension for the Azure CLI, installed with
> `az extension add --name azure-devops` into your `~/.azure` directory. Install
> it?

After a yes: `azdo-mine.sh install-deps`, which installs that one extension and
nothing else. The Azure CLI itself and `az login` are the user's own steps - the
script never does either.

## When to use

- Listing the work items assigned to you.
- Creating a Task under one of your items (auto-assigned to you).
- Changing fields (title, state, hours) on an item assigned to you.
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

`az login` and installing the Azure CLI are the user's own steps. The
`azure-devops` extension is needed once, and only with their agreement - see
"First run" above, then `azdo-mine.sh install-deps`.

## Quick reference

Run from the repo (org/project are parsed from the git remote unless overridden).

| Command | Does |
|---|---|
| `azdo-mine.sh whoami` | Print the verified acting account, org, project |
| `azdo-mine.sh list [--all-states]` | Work items assigned to you |
| `azdo-mine.sh show <id>` | Show one of your items |
| `azdo-mine.sh children <parent-id>` | Children of one of your items |
| `azdo-mine.sh create-task <parent-id> <title> [--completed-work N] [--state STATE]` | New Task under your item, assigned to you. No defaults: an omitted flag leaves that field unset |
| `azdo-mine.sh update <id> [--title TEXT] [--state STATE] [--completed-work N]` | Change fields on your item. Only the flags you pass are sent; every other field is left as it was |
| `azdo-mine.sh set-state <id> <state>` | Change the state of your item (a thin `update --state`; prints `old -> new`) |
| `azdo-mine.sh comment <id> <text>` | Add a discussion comment to your item. Text must be ONE quoted argument |
| `azdo-mine.sh install-deps` | Install the `azure-devops` az extension - only after the user agreed |

Every mutating command also takes `--allow-closed`, refused by default. See
"Closed items" above: it belongs on one approved command, not in your habits.

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
- **No invented fields.** `create-task` and `update` have no default hours and no
  default state; they only send what a flag asked for, and they print the
  resulting field set. `update` with no flags refuses instead of writing a no-op,
  the removed `--hours` flag is rejected as an unknown option rather than silently
  mapped to a field, and a non-numeric `--completed-work` refuses.
- **Closed items refuse.** State category `Completed`/`Removed` blocks `update`,
  `set-state`, `comment`, and `create-task` on a closed parent, until
  `--allow-closed` records that the user was asked. An unresolvable category also
  refuses.
- **Nothing is installed silently.** A missing Azure CLI, a missing
  `azure-devops` extension, or `use_dynamic_install=yes_without_prompt` all
  refuse with an explanation; only `install-deps` installs, and only the one
  extension.
- **No deletion.**

Run `./test-azdo-mine.sh` (offline, stubs `az`, creates nothing) to check these
guards still hold - it asserts on the exact arguments each command assembles.

## Example (the common flow)

```bash
export AZDO_EXPECTED_ACCOUNT="you@example.com"
azdo-mine.sh whoami                                   # confirm you are you
azdo-mine.sh list                                     # your open items
# Asked for: "add a task 'Migrate token to SecretStr' under 30769" - nothing else
azdo-mine.sh create-task 30769 "Migrate token to SecretStr"
# Asked for: "...make it Active, 2 hours spent"
azdo-mine.sh create-task 30769 "Rotate the CI secret" --state Active --completed-work 2
azdo-mine.sh children 30769                           # verify it landed
# Asked for: "rename 30780 to 'Harden the token provider'" - title only
azdo-mine.sh update 30780 --title "Harden the token provider"
azdo-mine.sh set-state 30775 "Resolved"               # only if 30775 is yours
```

## Common mistakes

- **Calling raw `az boards work-item update/create` directly.** That skips every
  guard - it will happily edit an item that is not yours or act as the wrong
  identity. Route through `azdo-mine.sh`.
- **Trusting `az account show` for identity.** It is the ARM identity and can
  differ from the Boards identity (and a PAT ignores it entirely).
- **Filling optional fields so the item "looks complete".** An empty
  `CompletedWork` is the honest state of a task nobody has worked yet.
- **Expecting a state at creation.** Azure DevOps starts every new item in `New`;
  a state can only be set by a follow-up update, which the script runs *only*
  when `--state` was passed.
- **Passing `@Me` to `--assigned-to`.** `@Me` is a WIQL macro, not an assignment
  value; the script assigns the resolved account email.
- **Splitting comment text across arguments.** `comment 30769 ping the reviewer`
  refuses: only one quoted argument guarantees the posted text is the text you
  were given.
- **Treating a refusal as an obstacle.** Closed item, missing extension,
  unresolvable state category - each one is a question for the user, and the
  answer is theirs to give.

## Red flags - stop and use the guard

- About to type `az boards work-item update --id ...` by hand.
- About to modify an item without knowing whether it is assigned to you.
- Reaching for a PAT to "make auth simpler".

All of these mean: run the operation through `azdo-mine.sh`.

## Red flags - stop and omit or ask

- About to type a number or state the requester never said out loud.
- Scrolling the parent or a sibling task to decide what a field "should" be.
- Retyping the title instead of pasting it, or "fixing" its wording.
- Adding a note, signature, or summary to a comment they wrote.
- Thinking "the field looks empty, so something is missing".
- Adding a second `--` flag to a command for a change nobody requested.
- Reaching for `--allow-closed` before the user has answered, or reusing it on
  the next command because it worked on the last one.
- Typing `az extension add`, `pip install`, or any installer to get unblocked.

All of these mean: omit the flag, or ask the one question - never both invent and
proceed.
