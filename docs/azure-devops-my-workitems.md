Quickstart:

```bash
npx skills add asapcoder12/agent-skills --skill=azure-devops-my-workitems
npx skills update azure-devops-my-workitems
```

[Source](../skills/azure-devops-my-workitems/SKILL.md)

## What it does

Works with the Azure Boards work items assigned to **you** — lists them, shows one, creates a Task under one, changes title, state or hours, adds a comment.

Every write goes through `azdo-mine.sh`, which fails closed. It verifies the acting identity against `AZDO_EXPECTED_ACCOUNT`, refuses to run if a PAT is set, and checks ownership server-side with `AssignedTo = @Me` before touching anything. It cannot edit someone else's item, and it cannot delete.

Two of its refusals matter more than the rest. **It never invents a field** — a value you did not name is not written, so a new Task stays in `New` with no hours on it, and the agent asks instead of guessing. And **a closed item is read-only**: anything whose state category is `Completed` or `Removed` refuses until you have been asked and answered.

## When to use it

Only when you ask for it by name or clearly mention your own work items. A work-item id sitting in a branch, commit or PR (`feature/30856/…`, `AB#30769`) is not a request to touch that item, and finishing a coding task is not a request to update its board.

Not for board administration, not for other people's items, not for deletion.

## How to use it

Once per shell:

```bash
az login
export AZDO_EXPECTED_ACCOUNT="you@example.com"   # unset means refuse
```

Org and project come from the git remote; override with `AZDO_ORG_URL` and `AZDO_PROJECT`. The `azure-devops` CLI extension is needed once: the skill reports that it is missing and waits, and `azdo-mine.sh install-deps` installs that one extension after you say yes. Nothing is installed on your machine unasked.

Then type `/azure-devops-my-workitems`, or just ask:

- "show my work items"
- "list the tasks under story 30769"
- "add a task 'Migrate token to SecretStr' under 30769"
- "rename 30780 to 'Harden the token provider'"
- "put 2 hours on item 30775"
- "set item 30775 to Resolved"
- "comment on 30775 that the migration is done"

Expect a question back when your request leaves a field unnamed — that is the design, not a stall. `azdo-mine.sh whoami` confirms which account it will act as, and changes nothing itself.
