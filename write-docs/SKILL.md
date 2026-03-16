---
name: write-docs
description: >
  Use this skill whenever the user asks you to write, draft, improve, review, or critique
  technical documentation for software or developer tools. Triggers include: "write docs",
  "write a tutorial", "write a how-to", "explain how X works", "document this", "write a
  README", "draft a guide", "write up X for the docs", "improve this doc", "review this
  doc", or any request to produce documentation of any kind. Always use this skill before
  writing any documentation — even a short paragraph intended for a docs site. Do not skip
  this skill for "quick" doc tasks; the classification step alone prevents the most common
  documentation mistakes.
---

# Documentation Writing Skill

## Orientation

This skill produces documentation for software and developer tools. The assumed reader is
a competent developer under time pressure — they know what they're doing, they don't need
hand-holding, and they will leave if the document wastes their time.

Read `references/diataxis.md` for quadrant rules.
Read `references/style.md` for voice, tone, and formatting rules.

---

## Phase 0 — Detect Diátaxis Usage

Before classifying or writing, determine whether this project uses the
Diátaxis framework. Check in this order (stop at first confirmation):

1. Read `~/.claude/CLAUDE.md` and any project `CLAUDE.md` — look for
   "Diátaxis", "diataxis", or explicit quadrant vocabulary (tutorial,
   how-to guide, explanation, reference).
2. Scan project docs (*.md, *.rst, *.adoc up to 3 levels deep) — look for
   headings or file names containing "tutorial", "how-to", "explanation",
   or "reference" used as structural categories.
3. If no evidence found, ask the user:
   > "Does this project follow the Diátaxis documentation framework
   > (tutorial / how-to / explanation / reference quadrants)?"

**If Diátaxis is confirmed:** proceed to Phase 1 (Classify) and enforce
quadrant rules from `references/diataxis.md`.

**If Diátaxis is NOT in use:** skip Phase 1. Apply only `references/style.md`
(voice, tone, formatting). Write the document in whatever structure best
serves the content — no quadrant constraints.

---

## Phase 1 — Classify Before Writing

Before writing a single word of documentation, state the classification explicitly:

```
QUADRANT: [Tutorial | How-To Guide | Explanation]
REASON: [one sentence]
```

Then check: does the user's request fit cleanly in one quadrant? If not, stop and say:

> "This request spans two quadrant types: [X] and [Y]. I'll need to write these as
> separate documents. Shall I start with [X]?"

### Classification decision tree

Ask these questions in order. Stop at the first match.

**Is the reader learning something new, guided step-by-step through a worked example?**
→ Tutorial

**Is the reader trying to accomplish a specific goal they already understand?**
→ How-To Guide

**Is the reader trying to understand something — why it works, what the tradeoffs are, the concepts behind it?**
→ Explanation

**Common misclassifications to catch:**

| Request phrasing | Likely mistake | Correct quadrant |
|---|---|---|
| "Explain how to set up X" | Sounds like Explanation, is actually a task | How-To Guide |
| "Tutorial on our config format" | Sounds like Tutorial, is actually reference | — (out of scope) |
| "Walk me through authentication" | Could be either — ask the user | Clarify first |
| "Document the X feature" | Underspecified — could be any quadrant | Clarify first |

---

## Phase 2 — Write to Quadrant Rules

After classifying, open `references/diataxis.md` and follow the rules for that quadrant
exactly. Then apply `references/style.md` throughout.

Do not deviate from quadrant structure. Do not add sections that belong to another
quadrant. If you feel the urge to add explanation to a how-to, or steps to an explanation,
that is a signal to link to a separate document, not to blend content here.

---

## Quadrant Quick Reference

| Quadrant | Reader's state | Reader's goal | Document's job |
|---|---|---|---|
| **Tutorial** | Learning | Build a working thing | Guide safely to success |
| **How-To Guide** | Working | Complete a specific task | Get out of the way |
| **Explanation** | Studying | Understand why/how | Build a mental model |

Reference documentation (API specs, config schemas, CLI flags) is out of scope for this
skill. Use a dedicated reference skill for those.
