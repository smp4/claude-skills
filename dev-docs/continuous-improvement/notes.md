## Consequences of LLMs

- Use specialised tools rather than generic: it reduces the decision space at inference time. Avoid making the model burn tokens and probability mass on composing command, flags, anticipate errors. An existing tool should handle existence checks, encoding, error messages (a `safe read` function)
- Skills should have narrow phases of work. Skills can have reference files for even narrower parts of work. Collapse open ended work into structred templates the model can follow.
- Triggers to use tools work better when they are based on structural events (eg. end of a phase, when a tool fails), rather than constant vigilence approaches (continuous monitoring and judgement). Maps to how attention works in transformers. For vigilence, the directive is buried in the system prompt. A trigger that fires at a structural boundary doesnt compete - it IS the task at the moment. 
  - *Any self-improvement needs to be event-driven.* NOT "always notice when you make mistakes". Instrument specific moments.
- Telemetry is the only thing that survives context windows. and it works.
- Models dont have the executive function to decide when a context switch is worth it (switch from task to improvement **now*). Self improvement needs to be its own phase.
- The human must remain as the meta-learning layer. LLM can't notice what it isn't noticing.
  - We can build a system that makes the humans meta-learning cheaper and faster.
- Session reflections from the LLM should be treated as *hypothesis generators* for the human to scan and action, not as ground truth.

Objectives: 

- Surface data, flagging patterns, making the "what should I improve" question easier to answer. 
- Should follow the scientific method!!
- what can we control? we dont control the foundation model, need to find ways to improve that dont touch the weights (no fine tuning available).
- close most of the loop between "agent makes mistake" and "agent never makes that mistake again."
- no vigilence requested of LLM. switch context on concrete events

non-goal

- meta-problem of skills-about-skills consuming the context budget they're meant to optimize


WHY NOT GSD

- strange crypto token , dont trust
- Your TDD-first, docs-first workflow is more disciplined. GSD's tasks are "do this, verify with curl" — useful for quick iteration, not for the engineering rigour you're building toward.
