# Session Summary: Persona Skills for Engineering Practice

## Purpose
This file gives Claude Code the context needed to build a set of practitioner persona skills for `~/.claude/skills/`. These skills shape how Claude approaches code generation, code review, plan creation, and architectural review — by embodying the values and judgment of specific thinkers rather than applying surface checklists.

## Core Design Decisions Made

### Persona skills have two modes
Each persona skill must distinguish between:
- **Construction mode**: Shapes how the artifact is created (what to optimise for, what to ask before writing)
- **Review mode**: Adversarial critical eye on an existing artifact (what would make this person wince, what bets are being made)

This mirrors the `/new-plan` → `/new-task` separation already in the skill system. Conflating construction and review produces weaker results from both.

### Adversarial plan review is a first-class workflow
The intended pattern is:
1. One primary persona constructs the plan (single voice = coherent plan)
2. Specialist personas review independently in parallel subagents, each checking a specific dimension
3. Human synthesises — this is the approval gate, not another agent

Fully automated agent-vs-agent debate has a ceiling: models tend toward false consensus or unresolvable deadlock. The value of adversarial review is surfacing *what the human needs to decide*, not deciding it.

### Reversibility is a first-class architectural concern
Patrick Kua's lens specifically: every significant decision in a plan/spec should be classified as cheap-to-reverse, expensive-to-reverse, or effectively-irreversible. This classification drives how much scrutiny and documentation (ADRs) is warranted.

## Personas to Build

### Core trio (foundational)
- Kent Beck — test-first, simplicity, communication through code
- Dave Farley — deployment pipelines, releasability as architectural constraint
- Martin Fowler — refactoring, patterns, domain boundaries

### High priority additions
- Michael Feathers — legacy code, seams, characterization tests, making unsafe code safe to change
- Sandi Metz — object design, dependency management, earning abstractions
- Ron Jeffries — XP values, emergent design, resisting premature complexity

### Evolutionary architecture specialists (this session's focus)
- Neal Ford + Rebecca Parsons — fitness functions, reversibility, architectural evolvability
- Patrick Kua — ADRs, decision reversibility classification, tech radar thinking
- Michael Nygard — operability, stability patterns, deployment tolerance
- Sam Newman — incremental migration, service decomposition
- Gregor Hohpe — architecture as enabling change, integration patterns

### Optional / situational
- Jessica Kerr — sociotechnical systems thinking
- Fred Brooks — essential vs accidental complexity
- John Ousterhout — deep modules, information hiding

## Key Principles for Skill Design

- **Capture the why, not just the what**: Values and decision heuristics, not checklists
- **Negative examples are load-bearing**: What would make this person wince in a review?
- **Context anchors**: The persona in greenfield design vs legacy review vs PR review behaves differently
- **Progressive disclosure**: Main SKILL.md lean, detail in reference files
- **Anti-anchoring**: When reviewing plans with telemetry/data, analyze data before reading hypothesis

## Files in This Package
- `SESSION-SUMMARY.md` — this file
- `persona-template/SKILL.md` — template for building any practitioner persona skill
- `ford-parsons-persona/SKILL.md` — Neal Ford + Rebecca Parsons (evolutionary architecture)
- `ford-parsons-persona/references/construction.md` — construction mode detail
- `ford-parsons-persona/references/review.md` — review mode detail
- `kua-persona/SKILL.md` — Patrick Kua (decision reversibility + ADRs)
- `adversarial-plan-review/SKILL.md` — workflow skill for adversarial plan creation + review
- `adversarial-plan-review/references/subagent-setup.md` — how to wire up parallel review subagents
