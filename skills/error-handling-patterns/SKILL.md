---
name: error-handling-patterns
description: Patterns for deciding how a system fails - exception hierarchies versus Result types, error propagation and wrapping, API error contracts, and retry, backoff, timeout, circuit-breaker and graceful-degradation policies. Use when the task is to choose or review an error strategy rather than fix one failing call - designing an error model, defining what an API returns on failure, adding resilience around a flaky or third-party dependency, or auditing how failures surface across a codebase. Triggers - "design the error model", "should this raise or return a Result", "add retry with backoff around this call", "this dependency is flaky, what policy fits", "our error handling is inconsistent", "what should this endpoint return on failure". Do NOT use for a single try/except, an ordinary bugfix, reading an existing stack trace, or debugging one failing test. Keywords - error handling, exception hierarchy, custom exceptions, Result type, error contract, circuit breaker, fault tolerance.
---

# Error Handling Patterns

Build resilient applications with robust error handling strategies that gracefully handle failures and provide excellent debugging experiences.

## Scope check

This skill is for choosing a **shape**, not for fixing one call. Confirm the task is
one of these before going further:

- Designing an error model or exception hierarchy for a new module or service
- Deciding the error contract an API returns - status codes, error bodies, error codes
- Picking a policy around a dependency you do not control - retry, backoff, timeout,
  circuit breaker, graceful degradation
- Choosing between exceptions and Result types for a boundary
- Auditing how failures surface across an existing module and making them consistent
- Deciding how errors cross an async or concurrency boundary

If instead the task is a single `try/except`, an ordinary bugfix, a stack trace to read,
or one failing test to debug, **say so and drop this skill** - just make the fix.

The patterns here are input, not law. Where the repo already has an error convention,
the convention wins, and the smallest change that fits it beats a redesign.

## Core Concepts

### 1. Error Handling Philosophies

**Exceptions vs Result Types:**

- **Exceptions**: Traditional try-catch, disrupts control flow
- **Result Types**: Explicit success/failure, functional approach
- **Error Codes**: C-style, requires discipline
- **Option/Maybe Types**: For nullable values

**When to Use Each:**

- Exceptions: Unexpected errors, exceptional conditions
- Result Types: Expected errors, validation failures
- Panics/Crashes: Unrecoverable errors, programming bugs

### 2. Error Categories

**Recoverable Errors:**

- Network timeouts
- Missing files
- Invalid user input
- API rate limits

**Unrecoverable Errors:**

- Out of memory
- Stack overflow
- Programming bugs (null pointer, etc.)

## Detailed patterns and worked examples

Detailed pattern documentation lives in `references/details.md`. Read that file when the navigation tier above is insufficient.

## Best Practices

1. **Fail Fast**: Validate input early, fail quickly
2. **Preserve Context**: Include stack traces, metadata, timestamps
3. **Meaningful Messages**: Explain what happened and how to fix it
4. **Log Appropriately**: Error = log, expected failure = don't spam logs
5. **Handle at Right Level**: Catch where you can meaningfully handle
6. **Clean Up Resources**: Use try-finally, context managers, defer
7. **Don't Swallow Errors**: Log or re-throw, don't silently ignore
8. **Type-Safe Errors**: Use typed errors when possible

```python
# Good error handling example
def process_order(order_id: str) -> Order:
    """Process order with comprehensive error handling."""
    try:
        # Validate input
        if not order_id:
            raise ValidationError("Order ID is required")

        # Fetch order
        order = db.get_order(order_id)
        if not order:
            raise NotFoundError("Order", order_id)

        # Process payment
        try:
            payment_result = payment_service.charge(order.total)
        except PaymentServiceError as e:
            # Log and wrap external service error
            logger.error(f"Payment failed for order {order_id}: {e}")
            raise ExternalServiceError(
                f"Payment processing failed",
                service="payment_service",
                details={"order_id": order_id, "amount": order.total}
            ) from e

        # Update order
        order.status = "completed"
        order.payment_id = payment_result.id
        db.save(order)

        return order

    except ApplicationError:
        # Re-raise known application errors
        raise
    except Exception as e:
        # Log unexpected errors
        logger.exception(f"Unexpected error processing order {order_id}")
        raise ApplicationError(
            "Order processing failed",
            code="INTERNAL_ERROR"
        ) from e
```

## Common Pitfalls

- **Catching Too Broadly**: `except Exception` hides bugs
- **Empty Catch Blocks**: Silently swallowing errors
- **Logging and Re-throwing**: Creates duplicate log entries
- **Not Cleaning Up**: Forgetting to close files, connections
- **Poor Error Messages**: "Error occurred" is not helpful
- **Returning Error Codes**: Use exceptions or Result types
- **Ignoring Async Errors**: Unhandled promise rejections
