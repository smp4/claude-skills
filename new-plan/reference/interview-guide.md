# Interview Guide — Reference

## Question bank by area

### Problem & motivation
- "What's the pain point today? Walk me through what happens."
- "Who experiences this problem? How often?"
- "What's the cost of NOT solving this?"
- "Have you tried other solutions? What fell short?"

### Desired outcomes
- "When this is done, what's the first thing you'd demo?"
- "Describe the ideal workflow from the user's perspective."
- "What metric improves when this ships?"
- "Is there a before/after you can describe concretely?"

### Scope boundaries
- "What are you explicitly NOT building in this iteration?"
- "If you had to ship in one week, what would you cut?"
- "Are there adjacent features people will expect that we should exclude?"
- "What's the minimum version that delivers value?"

### Constraints
- "What tech stack / language / framework is required?"
- "Are there existing systems this must integrate with?"
- "What are the performance targets? (latency, throughput, etc.)"
- "Are there security or compliance requirements?"
- "Where and how will this be deployed?"

### Interfaces
- "What data goes in? What format? Where does it come from?"
- "What data comes out? What consumes it?"
- "Are there existing API contracts or schemas to conform to?"
- "Who are the callers — humans, other services, scheduled jobs?"

### Edge cases & failure modes
- "What happens with empty input? Huge input? Malformed input?"
- "What if a dependency is unavailable?"
- "What should happen on partial failure?"
- "Are there concurrency or ordering concerns?"

### Acceptance criteria
- "How would you manually verify this works?"
- "Give me three concrete examples of correct behaviour."
- "Give me one example of something that should be rejected."
- "What would make you confident this is done?"

## Anti-patterns to avoid

### Asking too much at once
❌ "Tell me about the problem, who it's for, what tech stack,
   what the API looks like, and all the edge cases."
✅ "Let's start with the problem. What's the pain point today?"

### Accepting vague answers
❌ User: "It should be fast." → "OK, got it."
✅ User: "It should be fast." → "Can you quantify that?
   Under 200ms? Under 1s? For what payload size?"

### Leading the witness
❌ "You probably want a REST API with JSON, right?"
✅ "What kind of interface are you imagining? API, CLI, library, UI?"

### Premature solutioning
❌ "I'll use a Redis cache and a worker queue for this."
✅ "I want to make sure I understand the problem before we
   talk about solutions. Can you tell me more about..."

### Ignoring contradictions
❌ User said "real-time" earlier but now says "batch is fine" → ignore
✅ "Earlier you mentioned real-time processing, but just now
   you said batch is fine. Which is closer to what you need?"

## Summary template

After the interview, present this to the user:

```
## What I heard

**Problem**: [one sentence]
**For**: [who]
**Key outcomes**: [2-3 bullets]
**Scope**: [what's in] / [what's out]
**Constraints**: [tech, perf, security]
**Key interfaces**: [in/out shapes]
**Critical edge cases**: [top 3]
**Acceptance criteria**: [numbered list]

Does this capture it? Anything to add or change?
```
