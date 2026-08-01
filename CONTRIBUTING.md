# Contributing

## Adding a skill

1. Create `skills/<name>/SKILL.md`. The directory name and the `name` in the frontmatter must match.
2. Add `"./skills/<name>"` to the `skills` array in `.claude-plugin/plugin.json`.
3. Add a row to the catalog table in `README.md`, linking to `skills/<name>/SKILL.md`.
4. Add a bullet to the Skills block in `README.md`, in the form ``- `<name>` — <text>``. The dash is an em dash (—) with a space on each side; the validator matches that exact shape.
5. Run `npm run validate` and `npm test`. Both must pass — CI runs the same two commands.

Steps 2 to 4 are not optional politeness: the validator fails if any of them is missing, so a skill cannot ship without appearing everywhere it should.

## Writing the frontmatter

```yaml
---
name: my-skill
description: <what it does>. Use when <triggers>. Do NOT use for <anti-triggers>. Keywords - <search terms>.
---
```

Hard limits, enforced by the validator:

- `name` — at most 64 characters, lowercase letters, digits and single hyphens only, no `anthropic` or `claude`, equal to the directory name.
- `description` — non-empty, at most 1024 characters, no `<…>` tags.
- Body — at most 500 lines. Longer material goes in `references/` inside the skill directory, linked from `SKILL.md` one level deep.

Write the description in the third person, about the skill rather than to the reader. It is the only thing an agent sees before the skill fires, so it has to carry the anti-triggers as well as the triggers. `skills/azure-devops-my-workitems/SKILL.md` is the reference example.

## Writing the Skills-block bullet

The bullet and the description are deliberately different texts:

- The **description** is written for retrieval. It carries `Explicit triggers - "…"` phrasings and a `Keywords - …` tail so the agent can match a request against it.
- The **bullet** is written to constrain behaviour inside a project. Drop the search anchors; keep the operational substance and the prohibitions — what the skill is allowed to touch, and what it must never touch.

Keep the bullet to one sentence or two.

## Running the checks

```bash
npm test          # unit tests for the validator
npm run validate  # the repository's own invariants
```
