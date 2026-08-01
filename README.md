# agent-skills

Reusable [Agent Skills](https://www.skills.sh) for coding agents. Install any subset into Claude Code, Cursor, Codex, GitHub Copilot, Windsurf, Gemini, Cline and 60+ other harnesses with one command.

## Install

```bash
npx skills add asapcoder12/agent-skills
```

The installer asks three things:

1. **Which skills** to install — a multi-select list, pick any subset.
2. **Which agents** to install them for — it detects the harnesses on your machine and lets you choose.
3. **Symlink or copy** — symlink keeps them updatable with `npx skills update`.

Non-interactive equivalents:

```bash
npx skills add asapcoder12/agent-skills --list                     # show what is here, install nothing
npx skills add asapcoder12/agent-skills -s documentation-writer    # one named skill
npx skills add asapcoder12/agent-skills -a claude-code cursor      # named agents
npx skills add asapcoder12/agent-skills -g                         # install globally, not per project
npx skills add asapcoder12/agent-skills --copy                     # copy files instead of symlinking
npx skills add asapcoder12/agent-skills --all                      # everything, no prompts
```

Claude Code can install the whole catalog as a plugin instead:

```bash
claude plugins install asapcoder-skills
```

## Skills

| Skill | What it does |
|---|---|
| [`azure-devops-my-workitems`](skills/azure-devops-my-workitems/SKILL.md) | Reads and updates your own Azure Boards work items through a guard script that refuses anything that is not verifiably yours. |
| [`documentation-writer`](skills/documentation-writer/SKILL.md) | Writes or restructures a standalone document using the Diátaxis framework, via a clarify → outline → approval → write workflow. |
| [`error-handling-patterns`](skills/error-handling-patterns/SKILL.md) | Designs an error-handling strategy: exception hierarchies vs Result types, error contracts, retry, timeout, circuit breaker. |

## Recommended setup

Each skill's `description` already tells your agent what the skill does and when to reach for it, so the skills work as soon as they are installed. What a description cannot do is say what wins when a skill's advice collides with your project's own conventions, or stop the agent from reaching for a skill you did not mean.

A short section in your project's agent-instructions file fixes both. Copy everything inside the block below and paste it to your agent:

```
Add the Skills section below to this project's agent-instructions file — CLAUDE.md,
AGENTS.md, GEMINI.md, .cursor/rules/, or whatever file this harness reads for project
instructions. Put it where the project's other conventions live. Keep only the bullets
for skills that are actually installed here — check .claude/skills/, .agents/skills/, or
wherever this harness keeps them — and drop the rest. Keep the wording as written.

## Skills

Invoke by exact name, only on the tasks below. Skills *inform*; the conventions above in
this file always win.

- `azure-devops-my-workitems` — use only when the user invokes it by name or directly asks about their own Azure Boards work items: list/show the items assigned to them, create a Task under one, update fields on one, set an item's state, or comment on it (every write goes through `azdo-mine.sh`, which fails closed unless the item is verifiably theirs). Never trigger it from ordinary git, branch, PR, or build activity, or from any task where the user hasn't mentioned work items — and never use it to touch someone else's item
- `documentation-writer` — use when authoring or restructuring a standalone document: a new or reworked file under `docs/`, a README, or a Diátaxis tutorial/how-to/reference/explanation (runs a clarify → outline → approval → write workflow). Not for docstrings, code comments, log/exception text, commit/PR bodies, small doc fixes, or the agent-instructions file itself
- `error-handling-patterns` — use when designing a new error-handling strategy: an exception hierarchy, Result type, API error contract, or retry/circuit-breaker/timeout policy (its advice is input; the repo's own conventions and minimal, surgical changes win). Not for routine `try/except`, bugfixes, or reading an existing stack trace
```
