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

Claude Code can install the whole catalog as a plugin instead. Add the marketplace once, then install from it:

```bash
claude plugin marketplace add asapcoder12/agent-skills
claude plugin install asapcoder-skills@asapcoder12
```

`asapcoder12` is the marketplace, `asapcoder-skills` the plugin inside it. Updating later is `claude plugin update asapcoder-skills@asapcoder12`.

## Skills

| Skill | What it does |
|---|---|
| [`azure-devops-my-workitems`](docs/azure-devops-my-workitems.md) | Reads and updates your own Azure Boards work items through a guard script that refuses anything that is not verifiably yours. |
| [`documentation-writer`](docs/documentation-writer.md) | Writes or restructures a standalone document using the Diátaxis framework, via a clarify → outline → approval → write workflow. |
| [`error-handling-patterns`](docs/error-handling-patterns.md) | Designs an error-handling strategy: exception hierarchies vs Result types, error contracts, retry, timeout, circuit breaker. |

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

- `azure-devops-my-workitems` — use only when the user invokes it by name or directly asks about their own Azure Boards work items: list/show the items assigned to them, create a Task under one, update fields on one, set an item's state, comment on it, or attach a file to it (every write goes through `azdo-mine.sh`, which fails closed unless the item is verifiably theirs). Never trigger it from ordinary git, branch, PR, or build activity, or from any task where the user hasn't mentioned work items — and never use it to touch someone else's item
- `documentation-writer` — use when the deliverable is a document that stands on its own: a new or reworked page under `docs/`, a README, a getting-started or onboarding guide, an API reference page, a runbook, a migration guide, an architecture explainer, or a restructuring of a docs tree (runs a clarify → outline → approval → write workflow). Not for docstrings, code comments, log/exception text, commit messages, PR bodies, changelog entries, typo or link fixes, or the agent-instructions file itself
- `error-handling-patterns` — use when the task is to choose or review an error strategy rather than fix one failing call: an exception hierarchy, exceptions vs Result types, the error contract an API returns, a retry/backoff/timeout/circuit-breaker policy around a dependency you don't control, or an audit of how failures surface across a module (its advice is input; the repo's own conventions and minimal, surgical changes win). Not for a single `try/except`, an ordinary bugfix, reading an existing stack trace, or debugging one failing test
```
