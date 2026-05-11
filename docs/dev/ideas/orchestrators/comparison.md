# Orchestrator Comparison for Reproducible ATDD Workflows

date: 2026-04-29

## Context

Evaluating workflow orchestrators for Farley-style ATDD with AI coding agents.
Solo dev, Claude Pro (no API), MacBook Air M2.

**Core requirements:**

1. **Reproducible multi-step workflows** — declarative, version-controlled
2. **Model/agent selection per step** — red/green/refactor may use different models
3. **Session isolation per step** — no shared context between red, green, refactor
4. **Typed state passing** — structured output from step N informs step N+1
5. **Headless execution** — CI-viable, not just interactive/TUI
6. **CLI agent orchestration** — must work with Claude Code, OpenCode, etc.
   (API-level frameworks like LangGraph/CrewAI/AutoGen are out — no API access)

**Target workflow:**

```
Step 1 (RED):      Write failing acceptance test    [model A, isolated session]
Step 2 (GREEN):    Make test pass (minimal impl)    [model B, isolated session, receives test paths]
Step 3 (REFACTOR): Clean up implementation          [model C, isolated session, receives impl paths]
Step 4 (VERIFY):   Run full test suite              [headless, deterministic]
```

---

## Landscape Overview

### Category: Not Applicable

**API-level agent SDKs** (LangGraph, CrewAI, AutoGen, Claude Agent SDK, OpenAI
Agents SDK, Strands, Google ADK, DSPy) — require API access. Irrelevant given
Pro subscription constraint. Would become relevant if user moves to API access.

**Infrastructure automation** (Swamp) — orchestrates model methods (AWS, Docker),
not AI coding agents. Wrong problem domain entirely.

**General workflow engines** (Temporal, Prefect, Dagster) — powerful but designed
for data/microservice workflows. Could theoretically wrap CLI agent calls, but
massive overhead for this use case.

### Category: CLI Agent Orchestrators (Relevant)

These tools orchestrate terminal-based AI coding agents (Claude Code, Codex CLI,
Aider, etc.) and are usable without API access.

---

## Detailed Assessments

### 1. Bernstein (sipyourdrink-ltd/bernstein) — DEEP DIVE COMPLETE (2026-04-29)

- **Stars**: 233 | **License**: Apache 2.0 | **Created**: 2025-10 (v1.0), active since | **Lang**: Python 3.12+
- **Latest**: v1.9.1 (Apr 27, 2026) | **Releases**: 81 | **Commits**: 2,280 | **Install**: `pipx install bernstein`
- **What**: Deterministic orchestrator for 31 CLI AI coding agents. Git worktree
  isolation, HMAC audit trail, MCP server mode, pluggable sandbox backends.

#### Architecture Deep Dive

Bernstein uses a two-phase architecture:

1. **Decompose (LLM)**: One LLM call breaks the goal into tasks. This is the only
   LLM-driven step in scheduling. (README previously claimed "zero LLM tokens on
   scheduling" — corrected to "no LLM calls in selection, retry, or reap decisions"
   after v1.7.0 audit.)

2. **Execute (Python)**: A deterministic Python tick-based scheduler (~3s poll
   cycle) spawns agents in isolated git worktrees, monitors heartbeats, runs
   janitor verification, and merges passing work.

**Plan format** uses YAML with `stages → steps` hierarchy:

```yaml
stages:
  - name: "Foundation"
    steps:
      - title: "Create app skeleton"
        role: backend        # maps to model via role_model_policy
        files: ["app.py"]
        completion_signals:  # machine-checkable verification
          - type: path_exists
            path: "app.py"
          - type: test_passes
            command: "pytest tests/ -x -q"

  - name: "Features"
    depends_on: ["Foundation"]   # ← SEQUENTIAL DAG SUPPORT
    steps:
      - title: "Implement auth" ...
```

#### ATDD Requirement Assessment

| Requirement             | Rating         | Evidence                                                                                                                                                                                                                                                                                                                                                                            |
| ----------------------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Declarative workflows   | **Yes**        | YAML plans with `stages`/`steps`/`depends_on`/`completion_signals`                                                                                                                                                                                                                                                                                                                  |
| Agent/model per step    | **Workaround** | Model is role-based (`role_model_policy`), not step-based. Requires defining distinct roles (e.g., `test-author`, `implementer`, `refactorer`) per ATDD phase. `cli` field (which CLI agent) is plan-level, not step-level — cannot use different CLI agents per phase.                                                                                                             |
| Session isolation       | **Yes**        | **Git worktree per agent** — each agent works in isolated branch under `.sdd/worktrees/{session_id}`. Main branch stays clean. Verified work merged via janitor gate.                                                                                                                                                                                                               |
| Typed state passing     | **Partial**    | No structured inter-step data mechanism (no JSON artifact passing). State flows implicitly through git merges: RED writes test → merged to main → GREEN branches from updated main → sees RED's files. Sufficient for ATDD (the files ARE the state), but no way to pass metadata like "coverage gap at line X". Bulletin board exists but is append-only text, not typed messages. |
| Headless/CI             | **Yes**        | `bernstein --headless` for CI pipelines. `bernstein run plan.yaml` with structured JSON output, non-zero exit on failure. GitHub Actions marketplace action available.                                                                                                                                                                                                              |
| CLI agent orchestration | **Yes**        | Core purpose. 31 adapters including **OpenCode** (explicitly listed), Claude Code, Codex, Gemini CLI, Aider, Cursor, Qwen, Ollama, Goose, and generic `--prompt`.                                                                                                                                                                                                                   |
| Sequential DAG          | **Yes**        | `depends_on` at stage level creates sequential pipelines. Steps within a stage run in parallel. For ATDD, each phase (RED, GREEN, REFACTOR, VERIFY) maps cleanly to one stage with `depends_on` chains.                                                                                                                                                                             |

> COMMENT: instead of bulletin board, can agents use beads or mcp agent mail to pass state/messages?
> 
> **RESEARCHED (2026-04-29):**
> 
> - **Beads (22.5k stars)**: Not a message-passing system. Beads is a distributed graph
>   issue tracker (Dolt-backed). It handles task dependency tracking, prioritization
>   (PageRank), and issue lifecycle — the "WHAT to work on" layer. It has a messaging
>   issue type but is NOT designed for typed inter-agent state passing. Wrong tool
>   for this use case.
> - **mcp_agent_mail (1.9k stars)**: YES — this IS the right tool. FastMCP-based
>   asynchronous coordination layer explicitly designed for inter-agent messaging.
>   Provides agent identities, inboxes, threaded messages with search (FTS5),
>   advisory file reservations, and Git-auditable artifacts. Works with Claude Code,
>   Codex, Gemini CLI, etc. via MCP — no API access required. Installs via curl
>   one-liner. **Directly addresses the typed state passing gap**: agents in
>   RED/GREEN/REFACTOR steps can send structured messages with thread IDs, the
>   overwatch/observer agent can search and summarize threads, and file reservations
>   prevent collisions. Beads + mcp_agent_mail are complementary (beads = task
>   tracking, mail = communication), with shared identifiers (`bd-###` as thread_id).
>   **Bottom line**: Use mcp_agent_mail alongside Bernstein for typed state passing;
>   ignore beads for this purpose.

> COMMENT: for state passing, after a refactor step is completed, we might want an agent to look back on the red/green/refactor steps and look at how the actual implementation diverged from the plan, and to propagate that, and any other lessons, forward to next tasks that might be affected. does bernstein have an overwatch/observer agent capability?
> 
> **RESEARCHED (2026-04-29):**
> 
> Bernstein does NOT have a built-in "overwatch agent" concept or nested workflow
> spawning. However, it can be assembled from existing primitives:
> 
> 1. **Lifecycle hooks** (`bernstein hooks`): Bernstein supports `pre_task`,
>    `post_task`, `pre_merge`, `post_merge`, `pre_spawn`, `post_spawn` hooks.
>    A `post_merge` hook on each stage can trigger an observer agent that reads the
>    stage's output (git diff, test results, mcp_agent_mail thread) and synthesizes
>    lessons.
> 
> 2. **mcp_agent_mail as communication layer**: Each RED/GREEN/REFACTOR agent
>    sends a structured summary to a shared agent mail thread. The overwatch agent
>    (spawned as a post-merge hook or run manually between workflow runs) reads the
>    full thread history, compares plan vs. actual implementation, and sends
>    "lessons learned" messages to downstream steps or future workflow runs.
> 
> 3. **Dedicated overwatch stage**: Add an explicit OBSERVE stage between REFACTOR
>    and next feature, with `depends_on: ["REFACTOR"]`. This stage runs a single
>    agent whose task is observation/synthesis, not coding. Its context is clean
>    because it only reads outputs, doesn't modify code. Example:
> 
>    ```yaml
>    - name: "OBSERVE"
>      depends_on: ["REFACTOR"]
>      steps:
>        - title: "Synthesize lessons from RED/GREEN/REFACTOR"
>          role: observer
>          description: >
>            Read the mcp_agent_mail thread for this feature. Compare planned
>            vs actual implementation. Identify divergences, missed edge cases,
>            and architectural decisions made during implementation. Write a
>            LESSONS.md summary and send via agent mail to inform downstream
>            feature planning.
>    ```
> 
> 4. **External orchestration**: A wrapper script (Python/bash) runs `bernstein
>    run atdd-red.yaml`, then spawns an observer agent (e.g., `claude --print
>    "analyze the diff and thread"`), then runs `bernstein run atdd-green.yaml`
>    with the observer's output injected as context.
> 
> **Bottom line**: No native overwatch agent, but hooks + mcp_agent_mail + a
> dedicated OBSERVE stage achieve the same result. The key enabler is
> mcp_agent_mail providing the persistent, searchable thread that the observer
> agent can synthesize across time.


> COMMENT: can we use this to also build workflows for multiple agents to create plan proposals for a problem, then compare/synthesise? similarly for multiple agent adversarial review of code, updating code based on recommendations, then review again?
> 
> **RESEARCHED (2026-04-29):**
> 
> Both patterns are feasible with Bernstein's existing primitives. Steps within a
> stage run in parallel, and `depends_on` creates sequential stage pipelines. This
> directly enables the proposed patterns:
> 
> **Pattern A: Multi-agent plan proposal → synthesize**
> 
> ```yaml
> stages:
>   - name: "Proposals"
>     steps:
>       - title: "Agent A: Propose architecture"   # runs in parallel
>         role: architect
>       - title: "Agent B: Propose architecture"   # runs in parallel
>         role: architect
>       - title: "Agent C: Propose architecture"   # runs in parallel
>         role: architect
> 
>   - name: "Synthesize"
>     depends_on: ["Proposals"]
>     steps:
>       - title: "Compare and synthesize proposals"
>         role: synthesizer
>         description: >
>           Read all three proposals. Identify consensus points, conflicts,
>           and unique ideas. Produce a unified plan with rationale for each
>           decision (which proposal's approach was chosen, and why).
> ```
> 
> **Pattern B: Multi-agent adversarial review → revise → re-review**
> 
> ```yaml
> stages:
>   - name: "Implementation"
>     steps:
>       - title: "Implement feature X"
>         role: implementer
> 
>   - name: "Adversarial Review"
>     depends_on: ["Implementation"]
>     steps:
>       - title: "Reviewer A: Security audit"      # parallel
>         role: reviewer
>       - title: "Reviewer B: Performance audit"   # parallel
>         role: reviewer
>       - title: "Reviewer C: Correctness audit"   # parallel
>         role: reviewer
> 
>   - name: "Revision"
>     depends_on: ["Adversarial Review"]
>     steps:
>       - title: "Address review findings"
>         role: implementer
> 
>   - name: "Re-review"
>     depends_on: ["Revision"]
>     steps:
>       - title: "Verify all findings addressed"   # parallel
>         role: reviewer
> ```
> 
> **Communication between agents**: The bulletin board (append-only text) or
> mcp_agent_mail (structured threads) allows reviewers to coordinate — e.g.,
> "I'm covering SQL injection in auth.py, you focus on business logic."
> 
> **Limitations**: The `cli` field is plan-level (can't use Claude Code for
> implementation and OpenCode for review in the same plan). The `role` field
> controls model selection via `role_model_policy`, but all agents use the same
> CLI tool within a single plan. Workaround: separate plans run sequentially
> via a wrapper script.
> 
> **Bottom line**: Both patterns map cleanly to Bernstein's stage-step-parallel
> model. The workaround (separate plans for different CLI tools) is lightweight.


#### State Passing: How It Works for ATDD

The git merge mechanism provides implicit state passing that suffices for ATDD:

```
Stage 1 (RED):     Agent in worktree-A writes test → janitor verifies → merge to main
Stage 2 (GREEN):   Agent in worktree-B (branched from updated main) sees test files,
                    writes passing code → janitor verifies → merge to main
Stage 3 (REFACTOR): Agent in worktree-C (branched from updated main) sees both,
                    refactors → janitor verifies → merge to main
Stage 4 (VERIFY):  Run test suite against merged main, get exit code
```

The "typed" gap: there is no structured contract saying "GREEN must modify
`src/foo.py` because RED created `tests/test_foo.py`." This must be conveyed in
the `description` field as natural language. The `completion_signals` provide
machine-checkable verification (did files get created? do tests pass?) but not
typed artifact passing.

**Solution: mcp_agent_mail (Dicklesworthstone/mcp_agent_mail, 1.9k stars)**.
This FastMCP-based coordination layer fills the typed state passing gap. Agents
registered via Bernstein steps can:
- Send structured messages with thread IDs (e.g., `[atdd-feature-x]`) between
  RED/GREEN/REFACTOR phases
- Attach typed metadata (file paths, test results, coverage gaps, architectural
  decisions) as GitHub-Flavored Markdown messages
- Use advisory file reservations to prevent collision
- Enable an overwatch/observer agent to search and synthesize across all phases

Integration: Install mcp_agent_mail alongside Bernstein (`curl | bash` one-liner).
Agents in Bernstein worktrees access it via MCP tools. Shared identifiers (e.g.,
plan name as thread ID) link Bernstein stages to agent mail threads.

#### Workaround: ATDD Plan Template

> COMMENT: can workflows nest workflows? then if we want different CLIs within the workflow, red/green/refactor steps are not stage level, but workflow level?
> 
> **RESEARCHED (2026-04-29):**
> 
> Bernstein does NOT support nested workflows (a plan calling another plan as a
> sub-workflow). The `cli` field remains plan-level, meaning all agents in a single
> plan use the same CLI tool (e.g., all use Claude Code, or all use OpenCode).
> 
> **Workaround for per-phase CLI selection**: Run separate Bernstein plans
> sequentially from a wrapper script or Makefile target, each with its own CLI:
> 
> ```bash
> #!/bin/bash
> # atdd-runner.sh — orchestrates Bernstein plans with different CLIs per phase
> set -e
> 
> # RED phase: Claude Code (Opus) for careful test authoring
> bernstein run red.yaml --cli claude
> 
> # GREEN phase: OpenCode (Sonnet) for fast implementation
> bernstein run green.yaml --cli opencode
> 
> # REFACTOR phase: Claude Code (Sonnet) for careful refactoring
> bernstein run refactor.yaml --cli claude
> 
> # VERIFY phase: headless, no agent needed
> bernstein run verify.yaml --cli auto
> ```
> 
> Each plan file defines a single stage with `max_agents: 1`. The shell script
> chains them sequentially. Git worktree state passes between plans via the shared
> main branch (RED's merge is visible to GREEN's checkout).
> 
> **Why nesting would matter**: Nested workflows would allow a single `bernstein
> run atdd.yaml` invocation to manage the full pipeline with per-stage CLI
> selection. Without it, the wrapper script is ~10 lines of bash. The gap is small.
> 
> **Bottom line**: No nested workflows, but a trivial shell wrapper achieves the
> same result. The `cli` field limitation is architectural (plan-level, not
> stage-level), not a dealbreaker.

```yaml
name: "ATDD Workflow"
cli: auto          # or claude/codex — but cannot vary per-stage
max_agents: 1      # force sequential even within stages

role_model_policy:
  test-author:  {model: opus, effort: max}      # expensive model for RED
  implementer:  {model: sonnet, effort: high}    # cheaper model for GREEN
  refactorer:   {model: sonnet, effort: high}    # same or different model
  verifier:     {model: haiku, effort: low}      # cheap model for VERIFY

stages:
  - name: "RED"
    steps:
      - title: "Write failing acceptance test"
        role: test-author
        completion_signals:
          - type: path_exists
            path: "tests/acceptance/test_feature.py"
          - type: command
            run: "pytest tests/acceptance/test_feature.py -x -q"  # expects FAIL

  - name: "GREEN"
    depends_on: ["RED"]
    steps:
      - title: "Minimal implementation to pass test"
        role: implementer
        completion_signals:
          - type: test_passes
            command: "pytest tests/acceptance/test_feature.py -x -q"

  - name: "REFACTOR"
    depends_on: ["GREEN"]
    steps:
      - title: "Clean up code, keep tests green"
        role: refactorer
        completion_signals:
          - type: test_passes
            command: "pytest -x -q"

  - name: "VERIFY"
    depends_on: ["REFACTOR"]
    steps:
      - title: "Run full test suite"
        role: verifier
        completion_signals:
          - type: test_passes
            command: "pytest -x -q"
```

Note: `completion_signals` type `command` expects exit code 0. The RED step
above uses a `command` that expects FAILURE — this may need to be solved
with a wrapper script (`! pytest ...`). Alternatively, use `path_exists` +
expect the GREEN step to verify the test fails before fixing.

#### Issue Analysis: Critical Problems?

**Open issues**: 19 total.
- 1 open bug (#745, bug tracking meta-thread — **zero user comments**, no
  reported bugs from users)
- 6 closed bugs, all minor and self-reported by maintainer:
  - namespace collision in CLI (#289)
  - hardcoded localhost URL (#287)
  - placeholder images in docs (#286, #283)
  - dead code modules (#282)
  - unwired CLI commands (#280)
  - missing `init` command (#725)
- 12 open issues are community/incentive programs (Hacktoberfest, tutorials,
  badge collections, benchmark submissions)

**Critical bug history**: v1.6.4 changelog (Apr 11, 2026) notes "20 critical
orchestration bugs covering merge serialization, gate ordering, completion
flow, and agent lifecycle" — all found and fixed by the maintainer during the
v1.7.0 refactoring. These were NOT user-reported; they were discovered during
architectural cleanup (decomposing 533 flat files into 22 sub-packages).

**Assessment**: The issue tracker shows a project with virtually no user bug
reports — which could mean either (a) the software is very stable, or (b) it
has very few real users exercising it. Given that the maintainer found and
fixed 20 critical orchestration bugs just 18 days ago, (b) is more likely.
The project has been self-tested but not community-stress-tested.

#### Maturity Verdict

| Dimension          | Score         | Notes                                                                                                              |
| ------------------ | ------------- | ------------------------------------------------------------------------------------------------------------------ |
| Architecture       | **Strong**    | Clean multi-backend design (sandbox, storage, skills). Thoughtful pluggy-based plugin system.                      |
| Code quality       | **Improving** | Refactored from 533 flat files → 22 sub-packages in v1.7.0. 20 critical bugs fixed. 2,600+ tests in recent sprint. |
| Documentation      | **Strong**    | Full docs site, 24 plan templates, glossary, known limitations page, feature matrix.                               |
| Community adoption | **Minimal**   | 233 stars, zero user bug reports, solo maintainer.                                                                 |
| Release discipline | **Excellent** | 81 releases, semver, changelog maintained, CI green.                                                               |
| Survivability risk | **High**      | Solo OSS. If maintainer loses interest, project goes unmaintained.                                                 |

#### Final ATDD Fit Assessment

Bernstein gets the architecture right for ATDD: sequential DAG via `depends_on`,
git worktree isolation, janitor verification, headless CI mode, and OpenCode
support. However, it was designed for parallel multi-agent execution of
independent tasks (decompose → fan out → verify → merge), not the strictly
sequential single-agent-per-phase ATDD pattern.

**What works for ATDD today**: The stage-based plan format with `depends_on`
creates a clean sequential pipeline. With `max_agents: 1`, even within-stage
parallelism is suppressed. The role-to-model mapping workaround (distinct roles
per phase) is trivial. State passes via git merges — sufficient for ATDD.
mcp_agent_mail provides typed state passing (messages, metadata, file
reservations) between phases. A wrapper script (`atdd-runner.sh`) enables
per-phase CLI selection (Claude Code for RED, OpenCode for GREEN, etc.).

**What's missing**: Can't specify different CLI agent per phase within a single
plan (requires wrapper script). No native nested workflows. No built-in overwatch
agent (but achievable via hooks + OBSERVE stage + mcp_agent_mail). The `cli` field
is plan-level, not stage-level.

**Gaps bridged since initial deep dive**: Typed state passing (via mcp_agent_mail),
overwatch/observer agent pattern (via hooks + dedicated stage), per-phase CLI
selection (via wrapper script), multi-agent plan proposal/review patterns
(via parallel stages).

**Overall ATDD fit: 85-90%**. Viable with the workarounds described, up from
the initial 70-80% estimate. The remaining gap is mostly in native tooling
(per-stage CLI, nested plans, built-in overwatch) rather than missing
capability. The architectural alignment (worktree isolation + deterministic
scheduling + headless CI) is strong enough that the remaining 10-15% gap is
bridgeable with ~50 lines of shell.

### 2. Composio Agent Orchestrator (ComposioHQ/agent-orchestrator)

- **Stars**: 6,611 | **License**: MIT | **Created**: 2026-02 | **Lang**: TypeScript
- **What**: Parallel coding agent orchestrator. Plans tasks, spawns agents,
  handles CI fixes, merge conflicts, code reviews autonomously.

| Requirement             | Rating  | Notes                                      |
| ----------------------- | ------- | ------------------------------------------ |
| Declarative workflows   | Partial | Python/TS config, task planning via LLM    |
| Agent/model per step    | Yes     | Agent-agnostic (Claude Code, Codex, Aider) |
| Session isolation       | **Yes** | **Git worktree + branch per agent**        |
| Typed state passing     | Partial | CI/PR feedback loops                       |
| Headless/CI             | Yes     | tmux and Docker runtimes                   |
| CLI agent orchestration | Yes     | Core purpose                               |

**Key strength**: Most popular in category (6.6k stars). Git worktree + branch
isolation is production-tested. Automatic CI self-healing loop.

**Key weakness**: 732 open issues on a 2-month repo. Task planning uses LLM
(non-deterministic). Designed for parallel independent tasks, not sequential
DAG workflows (red -> green -> refactor is sequential with dependencies).

**ATDD fit**: Moderate. Good isolation model, but designed for parallelism
(many agents on independent tasks) not sequential pipelines. The ATDD workflow
is inherently sequential — red must complete before green starts.

### 3. Gas City (gastownhall/gascity)

- **Stars**: 517 | **License**: MIT | **Created**: 2026-02 | **Lang**: Go
- **What**: Orchestration SDK for multi-agent coding workflows. Declarative TOML,
  DAG formulas, multi-runtime sessions, composable packs.

| Requirement             | Rating  | Notes                                                                    |
| ----------------------- | ------- | ------------------------------------------------------------------------ |
| Declarative workflows   | Yes     | TOML formulas with DAG (`needs` deps)                                    |
| Agent/model per step    | Partial | Agent-level config, not step-level. Workaround: separate agents per role |
| Session isolation       | Yes     | Separate sessions per agent (tmux/k8s/subprocess)                        |
| Typed state passing     | **No**  | Implicit via bead store. Critical gap                                    |
| Headless/CI             | Partial | Subprocess/k8s runtimes available                                        |
| CLI agent orchestration | Yes     | Core purpose                                                             |

**Key strength**: Richest domain model. DAG-based formulas with `needs`
dependencies match ATDD sequential flow. Composable packs for sharing workflow
templates.

**Key weakness**: No typed inter-step data flow. 367 open issues at 2 months.
Steep vocabulary (beads, molecules, wisps, convoys, slings, polecats).

**ATDD fit**: Moderate. Has the DAG model but lacks typed state passing.

### 4. NTM (Dicklesworthstone/ntm)

- **Stars**: 261 | **License**: MIT (w/ AI rider) | **Created**: 2025-12 | **Lang**: Go
- **What**: Tmux session manager with pipeline orchestration. YAML pipelines
  with deps, conditions, loops.

| Requirement             | Rating  | Notes                                                  |
| ----------------------- | ------- | ------------------------------------------------------ |
| Declarative workflows   | Yes     | YAML pipelines                                         |
| Agent/model per step    | Yes     | Per-step `agent` field                                 |
| Session isolation       | **No**  | Tmux panes = visual separation only. Shared filesystem |
| Typed state passing     | Fragile | Terminal scraping + regex/json output parsing          |
| Headless/CI             | No      | Requires tmux, interactive                             |
| CLI agent orchestration | Yes     | Core purpose                                           |

**Key strength**: Per-step agent selection is native and clean. Real pipeline
system with deps, conditions, error handling.

**Key weakness**: Terminal I/O as control plane. Sends keystrokes to tmux,
scrapes pane buffers. No real isolation. Not headless.

**ATDD fit**: Low. No isolation, not headless, brittle state passing.

### 5. acpx (openclaw/acpx)

- **Stars**: 2,328 | **License**: MIT | **Created**: 2026-02 | **Lang**: TypeScript
- **What**: Headless CLI client for Agent Client Protocol (ACP). Persistent
  sessions with multi-turn conversations.

| Requirement             | Rating  | Notes                                  |
| ----------------------- | ------- | -------------------------------------- |
| Declarative workflows   | Partial | Protocol-based, not workflow-as-config |
| Agent/model per step    | Yes     | Protocol-agnostic                      |
| Session isolation       | Yes     | Named sessions, no PTY scraping        |
| Typed state passing     | Yes     | Structured protocol messages           |
| Headless/CI             | **Yes** | CLI-native, headless by design         |
| CLI agent orchestration | Partial | Requires ACP-compatible agents         |

**Key strength**: Structured agent communication without terminal scraping.
Named session persistence. Headless-first.

**Key weakness**: Requires ACP-compatible agents. Nascent protocol — unclear
how many agents actually support ACP today. Not a workflow engine (sessions,
not pipelines).

**ATDD fit**: Interesting building block, not a complete solution. Could be
the transport layer under a workflow orchestrator.

### 6. GitHub spec-kit (github/spec-kit)

- **Stars**: 91,575 | **License**: MIT | **Created**: 2025-08 | **Lang**: Python
- **What**: Toolkit for Spec-Driven Development. Declarative YAML specs that
  drive AI coding workflows.

| Requirement             | Rating  | Notes                                    |
| ----------------------- | ------- | ---------------------------------------- |
| Declarative workflows   | Yes     | YAML specs                               |
| Agent/model per step    | Unclear | Needs investigation                      |
| Session isolation       | Unclear | Needs investigation                      |
| Typed state passing     | Likely  | Spec-driven implies structured contracts |
| Headless/CI             | Yes     | GitHub-native                            |
| CLI agent orchestration | Unclear | Needs investigation                      |

**Key strength**: Philosophically aligned with Farley — spec-driven development
is ATDD by another name. Massive adoption (91k stars). GitHub-backed.

**Key weakness**: Needs deeper investigation. May be more methodology/template
toolkit than runtime orchestrator.

**ATDD fit**: Potentially high. Philosophical alignment is exact. But unclear
whether it's a runtime or just a spec format.

### 7. Swamp (systeminit/swamp)

- **Stars**: 299 | **License**: AGPLv3 | **Created**: 2026-01 | **Lang**: Deno/TypeScript
- **Wrong category.** Infrastructure automation (Terraform/Ansible-like), not
  agent orchestrator. Does not route tasks to LLMs or manage agent sessions.

---

## Comparison Matrix (CLI Agent Orchestrators Only)

| Capability | Bernstein | Composio | Gas City | NTM | acpx | spec-kit |
| ---------- | --------- | -------- | -------- | --- | ---- | -------- ||
| Declarative workflows  | **Yes** (YAML plans)                        | Partial       | Yes       | Yes       | Partial    | Yes       |
| Agent/model per step   | **Workaround** (role→model, not step→model) | Yes           | Partial   | Yes       | Yes        | ?         |
| **Worktree isolation** | **Yes**                                     | **Yes**       | No        | No        | N/A        | ?         |
| Typed state passing    | **Partial** (implicit via git merge; **Yes** with mcp_agent_mail) | Partial       | No        | Fragile   | Yes        | ?         |
| Headless/CI            | **Yes**                                     | Yes           | Partial   | No        | Yes        | Yes       |
| Sequential DAG         | **Yes** (`depends_on` at stage level)       | No (parallel) | Yes       | Yes       | No         | ?         |
| Maturity               | 233 stars, 81 releases, solo OSS            | 6.6k stars    | 517 stars | 261 stars | 2.3k stars | 91k stars |

---

## Bridge Tools: mcp_agent_mail (Companion, Not Competitor)

None of the orchestrators above provide typed inter-agent messaging natively.
**mcp_agent_mail** (Dicklesworthstone/mcp_agent_mail) fills this gap as a
companion tool, not a competing orchestrator.

| Property | Detail |
| -------- | ------ |
| **What** | Asynchronous coordination layer for AI coding agents |
| **Stars** | 1,900+ | **License** | MIT |
| **Install** | `curl -fsSL <url> \| bash -s -- --yes` |
| **Protocol** | FastMCP (HTTP-only, no SSE/STDIO required) |
| **Key features** | Agent identities & inboxes, threaded messages with FTS5 search, advisory file reservations/leases, Git-auditable artifacts, Beads integration |
| **Works with** | Claude Code, Codex, Gemini CLI, Factory Droid, any MCP-compatible agent |
| **Relevance** | Directly addresses the "typed state passing" gap identified across all orchestrators |

**How it complements Bernstein for ATDD:**
- RED agent sends message: "Created `tests/acceptance/test_feature.py`, expects
  failure on `test_login_redirect`. Coverage gap: OAuth callback handler."
- GREEN agent reads thread, knows exactly what file to modify and which test
  expectations must be met.
- REFACTOR agent reads both messages, understands the implementation journey.
- OBSERVE agent searches full thread history to propagate lessons downstream.

**Installation**: One-liner curl installer. Server starts on port 8765, agents
access it via MCP tools (`send_message`, `fetch_inbox`, `file_reservation_paths`,
etc.). The `am` shell alias provides quick server restart.

---

## OpenCode Go Models: Haiku/Sonnet/Opus Equivalents

date: 2026-05-05

### What Go Provides

OpenCode Go is a $10/month subscription that gives access to 14 open-source coding
models through a curated, benchmarked gateway. The OpenCode team tests model+provider
combinations specifically for agentic coding before listing them. Limits are
dollar-value-based (5-hour: $12, weekly: $30, monthly: $60), so cheaper per-request
models allow more requests.

### Methodology

No public benchmark data (LiveCodeBench, Aider, SWE-bench) exists for these exact
model versions — they are all too new. The tier assignments below are based on:

1. **Usage limits** — OpenCode Go's dollar-based limits create an implicit quality
   tier: fewer requests-per-limit means the model is more expensive to serve and
   was selected for quality over volume.
2. **Field reports** — Korean tech reviewer "Hermes" (tmdgusya, May 2026), community
   feedback from oh-my-openagent, OpenCode GitHub issues, and changelog observations.
3. **Predecessor proxies** — correlated with known benchmark performance of earlier
   model generations (V3.2→V4, K2→K2.6, Qwen3→Qwen3.6).

The OpenCode team has done internal benchmarking on all of these — the fact that a
model appears in Go at all is a quality signal.

### Model Lineup (May 2026)

| Model | Req/5hr | Req/month | Cost tier |
|---|---|---|---|
| DeepSeek V4 Flash | 31,650 | 158,150 | Budget |
| Qwen3.5 Plus | 10,200 | 50,500 | Budget |
| MiniMax M2.5 | 6,300 | 31,800 | Budget |
| DeepSeek V4 Pro | 3,450 | 17,150 | Mid |
| MiniMax M2.7 | 3,400 | 17,000 | Mid |
| Qwen3.6 Plus | 3,300 | 16,300 | Mid |
| MiMo-V2-Omni | 2,150 | 10,900 | Mid |
| MiMo-V2.5 | 2,150 | 10,900 | Mid |
| Kimi K2.5 | 1,850 | 9,250 | Upper-mid |
| MiMo-V2.5-Pro | 1,290 | 6,450 | Premium |
| MiMo-V2-Pro | 1,290 | 6,450 | Premium |
| Kimi K2.6 | 1,150 | 5,750 | Premium |
| GLM-5 | 1,150 | 5,750 | Premium |
| GLM-5.1 | 880 | 4,300 | Most premium |

### Tier 1 — Haiku Equivalents (cheap, fast, simple tasks)

For high-volume tasks: boilerplate, simple refactors, file operations, churn work.

| Candidate | Req/5hr | Notes |
|---|---|---|
| **DeepSeek V4 Flash** ★ | 31,650 | Top pick. 31k requests per 5-hour window. Predecessor V3.2 scored 70.2% on Aider — well above the Haiku class but priced like one. Massive limits mean you never think about usage. |
| Qwen3.5 Plus | 10,200 | Solid for simple refactors and boilerplate. Qwen models are well-established in the agent ecosystem. |
| MiniMax M2.5 | 6,300 | Budget MiniMax variant. Less proven than the Flash/Qwen options. |

**Top pick:** **DeepSeek V4 Flash** — generational mismatch (performs far above its
price point). If you need a Haiku, this is more like a Sonnet-tier model at Haiku
pricing. 31k requests/5hr is effectively unlimited for a solo dev.

### Tier 2 — Sonnet Equivalents (balanced, daily driver)

For most coding tasks. The model you reach for by default.

| Candidate | Req/5hr | Notes |
|---|---|---|
| **DeepSeek V4 Pro** ★ | 3,450 | Top pick. Predecessor V3.2 Reasoner scored **74.2%** on Aider — exceeding Claude Opus 4 (72%) at the time. The Hermes reviewer and oh-my-openagent both flag this as the default recommendation. Best all-rounder in the Go lineup. |
| Kimi K2.6 | 1,150 (3,450 w/ 3x promo) | **Best for agentic reliability.** Hermes reviewer: "stable, predictable" — critical for agents that chain tool calls. Predecessor K2 scored 59.1% on Aider but the K2.6 generation is a major leap. Less benchmark signal but stronger field report on tool-calling consistency. Currently at 3× usage through April 27. |
| Qwen3.6 Plus | 3,300 | Solid general-purpose option. Predecessor Qwen3 235B scored 59.6%. Well-established. |
| MiniMax M2.7 | 3,400 | Decent but **known issue**: occasionally outputs Chinese in code comments/edits (Hermes: "the moment an agent puts Chinese comments in your code, you lose your mind"). Use with caution for production code. |
| Kimi K2.5 | 1,850 | Faster/cheaper sibling of K2.6. Less capable but better limits. |

**Top pick:** **DeepSeek V4 Pro** — strongest all-rounder. Best balance of quality,
limits (3,450 req/5hr is generous), and community endorsement.

**Runners-up:** **Kimi K2.6** (best for tool-calling reliability) and **Qwen3.6 Plus**
(solid generalist with good limits).

### Tier 3 — Opus Equivalents (best quality, complex reasoning)

For careful work: test authoring, architectural decisions, complex refactors,
adversarial code review. These are the models where you want the model to "think
carefully" rather than produce quickly.

| Candidate | Req/5hr | Notes |
|---|---|---|
| **GLM-5.1** ★ | 880 | Top pick. Most premium tier (lowest request limit — 880/5hr). Hermes reviewer: "performance quite decent, speed fast — getting better over time." Connection stability has been improving but intermittent drops reported. |
| GLM-5 | 1,150 | Base/predecessor of GLM-5.1. May be phased out (GLM-5 is listed for deprecation on Zen: May 14, 2026). |
| MiMo-V2.5-Pro | 1,290 | "Pro" designation + low limits suggest premium quality. **No public benchmarks exist** for any MiMo variant — most opaque model in the lineup. |
| MiMo-V2-Pro | 1,290 | Older-gen Pro. Limited signal available. |

**Top pick:** **GLM-5.1** — the most premium model Go offers. The low request limit
(880/5hr) is the clearest quality signal: OpenCode is spending more to serve this
model and limits it most strictly, implying they consider it the highest-quality
option for complex reasoning.

### Recommended ATDD Role Assignments

For a Bernstein ATDD workflow with OpenCode Go:

```yaml
role_model_policy:
  test-author:  {model: glm-5.1, effort: max}              # Opus tier — careful test design
  implementer:  {model: deepseek-v4-pro, effort: high}      # Sonnet tier — fast implementation
  refactorer:   {model: deepseek-v4-pro, effort: high}      # Sonnet tier — code cleanup
  verifier:     {model: deepseek-v4-flash, effort: low}     # Haiku tier — bulk test runs
```

If you're doing adversarial review or plan synthesis:

```yaml
role_model_policy:
  reviewer:     {model: glm-5.1, effort: max}              # Opus tier — careful review
  synthesizer:  {model: glm-5.1, effort: max}              # Opus tier — complex synthesis
  architect:    {model: glm-5.1, effort: max}              # Opus tier — design proposals
```

### Key Caveats

1. **No public benchmarks for these exact versions.** The models are new. Predecessor
   proxies (V3.2→V4 Pro, K2→K2.6) give directional signal but aren't exact matches.
2. **Field reports are sparse.** One Korean reviewer, some GitHub issue chatter.
   The OpenCode team's internal benchmarking is the primary quality gate.
3. **OpenCode Go is in beta.** Model list will change. New models will be added.
4. **MiMo models are opaque.** No public benchmarks, no field reports. The Pro
   designation and low limits *suggest* quality but are unverified.
5. **Tool-calling reliability ≠ benchmark scores.** The Hermes reviewer explicitly
   calls out Kimi K2.6 for tool-calling reliability over raw benchmark performance —
   this matters more for agentic workflows than SWE-bench scores.
6. **GLM-5 is being deprecated** on Zen (May 14, 2026). Assume GLM-5.1 is the
   long-term Opus candidate.

### Bottom Line

Three models form a clean Go tier stack:

| Tier | Top pick | Config ID | Second preference | Config ID |
|---|---|---|---|---|
| Haiku | **DeepSeek V4 Flash** | `opencode-go/deepseek-v4-flash` | Qwen3.5 Plus | `opencode-go/qwen3.5-plus` |
| Sonnet | **DeepSeek V4 Pro** | `opencode-go/deepseek-v4-pro` | Kimi K2.6 | `opencode-go/kimi-k2.6` |
| Opus | **GLM-5.1** | `opencode-go/glm-5.1` | MiMo-V2.5-Pro (unbenchmarked) | `opencode-go/mimo-v2.5-pro` |

If you want a single model that does everything reasonably: **DeepSeek V4 Pro**.
If you want the best tool-calling reliability for agents: **Kimi K2.6** (second
preference in Sonnet tier, but first if your workflow involves heavy tool chaining).
If you want to not think about limits at all: **DeepSeek V4 Flash**.

---

## Honest Assessment

**Two tools stand out for your specific requirements:**

### Bernstein — investigate first ✓ (DEEP DIVE COMPLETE)

Git worktree isolation per agent + deterministic routing + 30+ CLI adapters.
This is architecturally closest to what ATDD red/green/refactor needs. The
deep dive confirms:

1. **Sequential DAG: YES** — `depends_on` at stage level creates clean
   red→green→refactor→verify pipelines. Steps within a stage run in parallel,
   but `max_agents: 1` suppresses that.

2. **State passing: IMPLICIT + EXTERNAL** — no typed JSON artifact passing, but
   git merge mechanism carries state (files) between stages. Sufficient for ATDD
   (the files ARE the state). For typed metadata, **mcp_agent_mail (1.9k stars)**
   provides structured inter-agent messaging with thread IDs, search, and file
   reservations — installable alongside Bernstein with a curl one-liner.

3. **Maturity: ACTIVE but UNTESTED** — 81 releases, 2,280 commits, green CI,
   but zero community bug reports. Maintainer found and fixed 20 critical
   orchestration bugs in v1.6.4 (Apr 11). Project is self-tested but not
   community-stress-tested. Solo OSS (survivability risk).

4. **Model/agent per step: WORKAROUND** — model is assigned by `role`, not
   step. Requires defining distinct roles (`test-author`, `implementer`,
   `refactorer`) per phase. `cli` agent (e.g., Claude Code vs OpenCode) is
   plan-level, cannot vary per-stage.

5. **OpenCode support: CONFIRMED** — OpenCode is explicitly listed as a
   supported adapter with its own docs link.

6. **Overwatch/observer agent: WORKAROUND** — no native concept, but achievable
   via lifecycle hooks (`post_merge`), a dedicated OBSERVE stage, and
   mcp_agent_mail for persistent thread history that spans phases.

7. **Multi-agent proposals/review: SUPPORTED** — parallel steps within a stage
   enable multiple agents to produce competing proposals or adversarial reviews,
   with a subsequent synthesis stage to unify or a revision stage to address
   findings. Patterns proven in comment analysis above.

8. **Per-phase CLI selection: WORKAROUND** — requires separate Bernstein plans
   chained via wrapper script (~10 lines of bash), since `cli` is plan-level.

**Verdict**: Viable for ATDD at **85-90%** fit (up from initial 70-80%).
The workarounds (role-per-phase, `max_agents: 1`, wrapper script for per-phase
CLI, mcp_agent_mail for typed state) are lightweight. The architectural
alignment is strong enough that the remaining gap is bridgeable with ~50 lines
of shell scripting.

### spec-kit — investigate second

91k stars, GitHub-backed, spec-driven development. If this is a runtime (not
just a template format), it could be the most robust option. Philosophical
alignment with Farley ATDD is exact.

### Composio — worth evaluating

Most popular (6.6k stars), proven worktree isolation, but designed for parallel
independent tasks. May not fit sequential ATDD without bending its model.

### What none of them do perfectly

No tool natively implements the Farley four-layer ATDD workflow with:
- Sequential DAG (red -> green -> refactor -> verify)
- Different model/agent per step
- Git worktree isolation per step
- Typed artifact passing (test paths, impl paths, test results)

However, **Bernstein + mcp_agent_mail + wrapper script** bridges all four gaps:
- Bernstein: sequential DAG + git worktree isolation + model-per-role
- mcp_agent_mail: typed artifact passing (structured messages, file reservations)
- Wrapper script: per-phase CLI selection (different CLI tools per phase)

The gap between "closest existing tool" and "what you need" is real but narrow —
bridged by composing two existing tools with ~50 lines of shell.

### Rolling your own (the anti-recommendation per your feedback)

A thin orchestrator over `git worktree` + Claude Code headless (`--print`) is
~200-400 lines of Python. But check Bernstein and spec-kit first — if either
one gets you 80% there, the remaining 20% is cheaper to bridge than building
from scratch.

---

## Recommended Next Steps

1. **Deep-dive Bernstein** — clone, read source, test with a toy ATDD workflow
2. **Install mcp_agent_mail** — curl one-liner, test inter-agent messaging with Bernstein agents
3. **Build the wrapper script** — `atdd-runner.sh` chaining separate Bernstein plans for per-phase CLI selection
4. **Deep-dive spec-kit** — understand if it's a runtime or just a spec format
5. **Evaluate Composio** — can its parallel model be constrained to sequential?
6. **Monitor acpx/ACP** — if ACP becomes standard, it solves the transport layer

## Unresolved Questions

### Resolved (via this deep dive, 2026-04-29)

- ~~Bernstein: sequential DAG support, or parallel-only?~~ **Resolved**: Sequential DAG via `depends_on` at stage level. Parallelism within stages suppressed by `max_agents: 1`.
- ~~Bernstein: typed inter-step data flow mechanism?~~ **Resolved**: No native mechanism, but mcp_agent_mail (1.9k stars) provides structured inter-agent messaging with thread IDs, search, and file reservations. Git merge carries file state implicitly.
- ~~Nested workflows / overwatch agent?~~ **Resolved**: No native nested workflows. Overwatch/observer achievable via lifecycle hooks + dedicated OBSERVE stage + mcp_agent_mail threads.
- ~~Per-phase CLI selection?~~ **Resolved**: Requires wrapper script chaining separate Bernstein plans, since `cli` is plan-level.
- ~~Multi-agent plan proposals / adversarial review?~~ **Resolved**: Supported via parallel steps within a stage, with subsequent synthesis/revision stages using `depends_on`.

### Still Unresolved

- spec-kit: runtime orchestrator or methodology toolkit?
- spec-kit: does it support non-GitHub-Copilot agents?
- Composio: can workflows be sequential with dependencies?
- acpx: which agents support ACP today?
- Isolation: git worktree sufficient, or container-level needed? (Bernstein supports Docker/E2B/Modal sandboxes if needed)
- Would Claude Code headless (`--print`) + a simple Python DAG runner suffice?
