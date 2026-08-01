Quickstart:

```bash
npx skills add asapcoder12/agent-skills --skill=error-handling-patterns
npx skills update error-handling-patterns
```

[Source](../skills/error-handling-patterns/SKILL.md)

## What it does

Gives the agent a working vocabulary for error design: exceptions versus Result types, where to wrap a failure and where to let it through, and the four resilience policies — retry, timeout, circuit breaker, graceful degradation.

Its advice is input, not law. Where your repo already has a convention, the convention wins. Detail it does not need up front lives in `references/details.md` and is pulled in only when the question calls for it.

## When to use it

When you are deciding a shape: an exception hierarchy, an API error contract, a policy around a dependency you do not control, or a review of how failures surface across a module.

Not for a single `try/except`, not for an ordinary bugfix, and not for reading a stack trace you already have — those need the fix, not a strategy.

## How to use it

Nothing to set up. The agent reaches for it on its own when a task is about error design; force it with `/error-handling-patterns`.

- "design the error model for this API"
- "should this return a Result or raise?"
- "add retry with backoff around this call"
- "this dependency is flaky — what policy fits?"
- "review how failures surface in this module"
