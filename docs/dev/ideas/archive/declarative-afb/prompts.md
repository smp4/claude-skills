## plan polish

Carefully review this entire plan and come up with your best revisions in terms of better architecture, features, changed features, etc. to make it better, more robust/reliable, more performant, more compelling/useful, etc.

For each proposed change, give me your detailed analysis and rationale/justification for why it would make the project better along with the git-diff style changes relative to the original markdown plan at @docs/dev/ideas/declarative-afb/plan.md

PES: if we're getting to low levels of change in the plan, such that reviews are well scoped, can switch to sonnet reviews.
...

Do this again, and actually be super super careful: can you please check over the plan again and compare it to all that feedback I gave you? I am positive that you missed or screwed up at least 80 elements of that complex feedback.

when to stop:

When to stop refining and start converting to beads: Stay in plan refinement if whole-workflow questions are still moving around, major architecture debates are still open, or fresh models keep finding substantial missing features, constraints, or tradeoffs. Switch to beads when the plan mostly feels stable and the remaining improvements are about execution structure, testing obligations, sequencing, and embedded context rather than about what the system fundamentally is. If you are still redesigning the product, stay in plan space. If you are mainly packaging the work for execution, move to bead space.

## create beads

please take ALL of that and elaborate on it more and then create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.) Use only the `br` tool to create and modify the beads and add the dependencies. Use ultrathink.

Self-contained: Beads must be so detailed that you never need to refer back to the original markdown plan. Every piece of context, reasoning, and intent should be embedded.
Rich content: Beads can and should contain long descriptions with embedded markdown. They don't need to be short bullet-point entries. You can embed snippets of markdown inside the beads and they often do; JSONL is just how they serialize.
Complete coverage: Everything from the markdown plan must be embedded into the beads. Lose nothing in the conversion.
Explicit dependencies: The dependency graph must be correct; this is what enables bv to compute the optimal execution order.
Include testing: Beads should include comprehensive unit tests and e2e test scripts with great, detailed logging.

expect 200-500 beads for complex

## beads polish

Reread AGENTS.md so it's still fresh in your mind. Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things!

DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY!

Also, make sure that as part of these beads, we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Remember to ONLY use the `br` tool to create and modify the beads and to add the dependencies to beads. Use ultrathink.

## close to convergence

First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Use ultrathink. 

then 

We recently transformed a markdown plan file into a bunch of new beads. I want you to very carefully review and analyze these using `br` and `bv`. Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! Use ultrathink.

and dedup:

Reread AGENTS.md so it's still fresh in your mind. Check over ALL open beads. Make sure none of them are duplicative or excessively overlapping... try to intelligently and cleverly merge them into single canonical beads that best exemplify the strengths of each.

## ATDD


## agents pre reqs

- beads
- bv
- ubs

## new features

Come up with 30 ideas for improvements, enhancements, new features, or fixes for this project. Then winnow to your VERY best 5 and explain why each is valuable.


## imaginging

I want you to clone https://github.com/<external-project> to tmp and then investigate it and look for useful ideas that we can take from that and reimagine in highly accretive ways on top of existing <your project> primitives that really leverage the special, innovative concepts and value-add from both projects to make something truly special and radically innovative. Write up a proposal document, PROPOSAL_TO_INTEGRATE_IDEAS_FROM_<EXTERNAL>_INTO_<YOUR_PROJECT>.md

always too conservative, so: 

OK, that's a decent start, but you barely scratched the surface here. You must go way deeper and think more profoundly and with more ambition and boldness and come up with things that are legitimately "radically innovative" and disruptive because they are so compelling, useful, accretive, etc.

then invert


Now "invert" the analysis: what are things that we can do because we are starting with <your unique primitives/capabilities> that <the external project> simply could never do even if they wanted to because they are working from far less rich primitives that do not offer the sort of guarantees we have?

Look over everything in the proposal for blunders, mistakes, misconceptions, logical flaws, errors of omission, oversights, sloppy thinking, etc.

OK now we need to make the proposal self-contained so that we can show it to another model such as GPT Pro and have that model understand absolutely anything that might be relevant to understanding and being able to suggest useful revisions to the proposal or to find flaws in the plans. To that end, I need you to add comprehensive background sections about what <your project> is and how it works, what makes it special/compelling, etc. And then do the same in another background section all about <external project> and what it is and what makes it special/compelling, how it works, etc.

How can we improve this proposal to make it smarter and better-- to make the most radically innovative and accretive and useful and compelling additions and revisions you can possibly imagine. Give me your proposed changes in the form of git-diff style changes against the file below, which is named PROPOSAL_TO_INTEGRATE_IDEAS_FROM_<EXTERNAL>_INTO_<YOUR_PROJECT>.md:

<the complete proposal document>