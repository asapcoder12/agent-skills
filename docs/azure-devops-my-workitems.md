Quickstart:

```bash
npx skills add asapcoder12/agent-skills --skill=azure-devops-my-workitems
npx skills update azure-devops-my-workitems
```

[Source](../skills/azure-devops-my-workitems/SKILL.md)

## What it does

Works with the Azure Boards work items assigned to **you** — lists them, shows one, creates a Task under one, changes state, adds a comment.

Every write goes through `azdo-mine.sh`, which fails closed. It verifies the acting identity against `AZDO_EXPECTED_ACCOUNT`, refuses to run if a PAT is set, and checks ownership server-side with `AssignedTo = @Me` before touching anything. It cannot edit someone else's item, and it cannot delete.

## When to use it

Only when you ask for it by name or clearly mention your own work items. It stays out of ordinary git, branch, PR and build work on purpose — an agent that edits a tracker on its own initiative is worse than one that does nothing.

Not for board administration, not for other people's items, not for deletion.

## How to use it

Once per shell:

```bash
az extension add --name azure-devops        # first time only
az login
export AZDO_EXPECTED_ACCOUNT="you@example.com"   # unset means refuse
```

Org and project are read from the git remote; override with `AZDO_ORG_URL` and `AZDO_PROJECT`.

Then type `/azure-devops-my-workitems`, or just ask:

- "show my work items"
- "what's assigned to me in Azure Boards"
- "list the tasks under story 30769"
- "add a task to work item 30769"
- "set item 30775 to Resolved"
- "comment on work item 30775 that the migration is done"

Run `azdo-mine.sh whoami` first if you want to confirm which account it will act as before it writes anything.
