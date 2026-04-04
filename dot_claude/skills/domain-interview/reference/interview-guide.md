# Domain Interview Guide — Reference

## Phase 0: Orient — question bank

- "What is the feature or capability we're exploring today?"
- "Who is the primary person using this, and what are they trying to do?"

Limit to 1-2 questions. Get the topic and primary actor, then move on.

---

## Phase 1: Example Collection — question bank

### Normal path
- "Walk me through the normal case — what happens step by step?"
- "Can you give me a real example of that?"
- "What does the user see/get/receive when this works?"

### Preconditions
- "What needs to be true before this can start?"
- "What state does the system need to be in?"

### Success criteria
- "What does success look like exactly?"
- "How would you know this worked if you were watching someone use it?"

### Negative / unhappy paths
- "What's a case where this should NOT be allowed?"
- "What happens if something goes wrong in the middle?"
- "What's the most common mistake people make here?"

### Edge cases
- "What's a case where this is tricky?"
- "Are there any special cases your team always has to watch out for?"
- "What happens if there are zero items? Thousands?"

### Probing vague answers
- "Can you give me a concrete example of that?"
- "What exactly does that look like?"
- "Walk me through that step by step."

---

## Phase 2: Language Precision — question bank

### Synonym detection
- "You've used the words X and Y — are these the same thing or different?"
- "Your team says 'reservation' and 'booking' — is there a difference?"

### Canonical naming
- "What do you call this thing? What does your team call it?"
- "Is there a word you'd use that I haven't used yet?"
- "If you were writing this in a formal document, what word would you use?"

### Verb precision
- "When you say 'process the order', what specifically happens?"
- "What does 'validate' mean here? What makes it valid or invalid?"
- "Is 'submit' and 'send' the same action, or different steps?"

### Concept splitting
- "Is this one thing or two? Could they happen independently?"
- "You said 'it depends' — on what exactly? Let's map out each case."

---

## Phase 3: Boundaries — question bank

### Scope
- "What is outside the scope of what we're designing today?"
- "If we only had a week, what would we drop?"

### Dependencies
- "Does this touch any other part of the system?"
- "What does this depend on? What depends on it?"

### Failure modes
- "What happens when the external service is unavailable?"
- "What does the system do if this data is missing?"

### Context boundaries
- "Is this the same 'order' as in that other area, or a different concept?"
- "Would everyone in this context use this word the same way?"

---

## Verbatim capture rules

When the domain expert gives a concrete example:

1. **Record their exact words.** Do not rephrase, summarise, or
   clean up the language.
2. **Use quote blocks** in your notes: `> "their exact words"`
3. **If you're unsure**, read it back: "I heard you say X — is that
   exactly right, or would you say it differently?"

Why: paraphrasing introduces the exact ambiguity the interview is
designed to remove. The expert's words carry precise meaning that
a restatement may subtly change.

---

## Draft presentation protocol

When presenting the draft DOMAIN.md in Phase 4:

### Framing (say this before presenting)

> "I've drafted these based on what you told me. I may have made
> assumptions or used language that doesn't quite capture your
> meaning. Please correct anything that doesn't sound right —
> including terms that seem close but are not quite the word you'd
> use."

### Present in sections

Don't dump the whole document at once. Present each section and ask:

1. **Actors + business rules** → "Do these capture what you described?"
2. **Key examples** → "Did I capture your examples correctly?"
3. **Glossary terms** → "Does each term mean what you mean?"

### After corrections

- Revise the specific section
- Re-present the revised version
- Ask again: "Is this right now?"

### Approval gate

The expert must explicitly approve. Acceptable signals:
- "Yes, that's right"
- "Approved"
- "Looks good" (with no hesitation or qualifiers)

NOT acceptable:
- Silence
- "I guess so"
- "Sure" (if said quickly without reading)
- Changing the subject

If in doubt, ask directly: "Are you happy with this, or is there
anything to change?"

---

## Anti-patterns to avoid

### Asking too much at once
❌ Five questions in a single turn
✅ Two questions, wait, summarise, then two more

### Paraphrasing examples
❌ Expert: "The customer clicks 'archive' and the todo disappears"
   You: "So the todo is removed from the active list"
✅ Record: > "The customer clicks 'archive' and the todo disappears"

### Using technical language with non-technical experts
❌ "What's the API contract for this endpoint?"
✅ "What information does the system need to do this?"

### Accepting "it depends" without mapping the cases
❌ "It depends on the customer type" → "OK, got it"
✅ "What are the customer types? What happens differently for each?"

### Skipping the unhappy path
❌ Only discussing success scenarios
✅ "We've talked about how this works when everything goes right.
   What are the ways it goes wrong?"
