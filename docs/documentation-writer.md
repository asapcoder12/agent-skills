Quickstart:

```bash
npx skills add asapcoder12/agent-skills --skill=documentation-writer
npx skills update documentation-writer
```

[Source](../skills/documentation-writer/SKILL.md)

## What it does

Writes or restructures a standalone document using the Diátaxis framework, which splits documentation into four kinds with different jobs: a **tutorial** teaches a newcomer by doing, a **how-to guide** solves one stated problem, a **reference** describes the machinery, and an **explanation** discusses why.

It does not start writing straight away. First it settles which of the four you need, who reads it, what they are trying to achieve, and what stays out of scope — then it proposes an outline and waits for you to approve it.

## When to use it

For a document that stands on its own: a new or reworked file under `docs/`, a README, a getting-started guide, an architecture explainer.

Not for docstrings, code comments, log and exception text, commit or PR bodies, typo-level fixes, or the agent-instructions file itself. Those are edits inside other work, not documents.

## How to use it

Nothing to set up. Type `/documentation-writer`, or just ask:

- "write a getting-started guide for this project"
- "turn these notes into a how-to"
- "restructure docs/ — it's a mess"
- "we need a reference page for this API"
- "explain why we chose this architecture, as a doc"

Expect questions before any prose, and an outline to approve. Answer the questions rather than telling it to skip ahead — the outline is only as good as they are.
