# Stability Patterns — Concept Reference

last-updated: 2026-03-08

## Core Concept

Systems fail at their integration points. Every call to an external service,
database, or network resource is a potential failure propagation path. Stability
patterns prevent cascading failures by containing the blast radius.

## When to Apply

Any time the system makes network calls, depends on external services, or
has components that can fail independently. Skip this for purely in-process,
single-service code with no external dependencies.

## Patterns

### Circuit Breaker
**Problem**: repeated calls to a failing service waste resources and delay
recovery.
**Solution**: after N failures, stop calling. Periodically probe to detect
recovery. Three states: closed (normal), open (failing fast), half-open
(probing).
**Apply when**: any external service call. Essential for anything user-facing.

### Timeout
**Problem**: a slow dependency ties up resources indefinitely.
**Solution**: every external call has an explicit timeout. No call waits
forever. Combine with retry budget (not infinite retries).
**Apply when**: always. No external call should lack a timeout.

### Bulkhead
**Problem**: one failing dependency exhausts shared resources (threads,
connections), taking down unrelated functionality.
**Solution**: isolate resource pools per dependency. Failure in one pool
doesn't starve others.
**Apply when**: multiple external dependencies share a resource pool.

### Retry with Backoff
**Problem**: transient failures are normal but naive retry creates load spikes.
**Solution**: retry with exponential backoff + jitter. Cap total retries.
Distinguish transient (retry) from permanent (fail fast) errors.
**Apply when**: transient failures are expected (network, rate limits).

### Fallback / Graceful Degradation
**Problem**: a dependency failure makes the entire feature unavailable.
**Solution**: define degraded behaviour. Cached data, default values, or
reduced functionality is better than an error page.
**Apply when**: the feature can provide partial value without full dependency.

## Review Checklist

For each external dependency in the design:

1. **Timeout**: is there an explicit timeout? What value?
2. **Failure mode**: what happens when this dependency is down?
3. **Blast radius**: can this failure affect unrelated features?
4. **Recovery**: how does the system detect that the dependency is back?
5. **Load**: can retry behaviour create a thundering herd?

## Plan Integration

When a plan involves external dependencies, flag them:

```markdown
## External dependencies

| Dependency | Failure mode | Stability pattern | Fallback |
|---|---|---|---|
| [service/DB/API] | [what breaks] | [timeout/circuit breaker/etc] | [degraded behaviour] |
```

Skip this section when the plan has no external dependencies.
