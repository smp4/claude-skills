# Dave Farley — ATDD, Four-Layer Model, and AI-Assisted Development

## Overview

Dave Farley (co-author of *Continuous Delivery*, author of *Modern Software
Engineering*) advocates acceptance test-driven development (ATDD) as the
primary discipline for working safely with AI code generation. His position
is that as AI generates more code faster, the bottleneck shifts from writing
code to *verifying behaviour* — and the four-layer model provides the
architecture to do that at scale.

---

## Core Thesis: Verification Is the Bottleneck

In traditional development, much of the craft is defining solutions —
choosing data structures, algorithms, control flow. With AI, code generation
becomes cheap. The hard part becomes understanding and validating behaviour.

Farley's argument: because AI can generate enormous volumes of code (he cites
reports of 12,000+ lines/day), manual inspection is no longer a viable trust
mechanism. You cannot read 12,000 lines carefully enough to feel you truly own
them. The trust has to come from **executable specifications and continuous
verification**, not from manual inspection.

This changes the nature of programming. The developer's role shifts toward
defining the problem in greater detail — writing clear, detailed, executable
examples — and letting the AI generate implementations.

---

## Acceptance Tests as the Specification Language for AI

Farley's key practical insight: **acceptance tests expressed in a DSL are
far more reliable prompts for AI code generation than natural language**.

- Natural language prompts are ambiguous — the AI fills gaps with assumptions
- Executable specifications are precise — the AI has a verifiable contract
- The test suite *is* the verification mechanism — generated code either
  passes or it doesn't

He describes ATDD as potentially a "fifth-generation programming language"
for AI: the developer writes executable specifications; the AI writes the
implementation; the test suite determines correctness.

Farley's own Continuous Delivery team has experimented with this approach
using Claude Code, running an AI-ATDD workflow where acceptance tests drive
agentic code generation.

---

## The Four-Layer Model

The four-layer model separates *what the system does* from *how it does it*,
producing acceptance tests that are stable in the face of implementation
change and reusable across multiple interfaces.

```
┌─────────────────────────────────────────────┐
│  Layer 1: Acceptance Test (Executable Spec) │
│  Written in BDD/Given-When-Then style.       │
│  Describes business behaviour only.          │
│  Should NOT change unless business rules     │
│  change. No implementation detail here.      │
└────────────────────┬────────────────────────┘
                     │ calls
┌────────────────────▼────────────────────────┐
│  Layer 2: DSL (Domain Specific Language)    │
│  Business vocabulary in code.               │
│  e.g. user.hasCompletedTodo("Buy milk")     │
│       order.confirmFulfillment()            │
│  Defines WHAT operations exist.             │
│  No knowledge of HOW they are executed.     │
└────────────────────┬────────────────────────┘
                     │ calls
┌────────────────────▼────────────────────────┐
│  Layer 3: Protocol Driver                   │
│  Implements the DSL for a specific          │
│  interface (HTTP, UI, CLI, direct call).    │
│  Translates DSL operations into concrete    │
│  system interactions.                       │
│  Swap drivers to test different interfaces  │
│  with the same acceptance tests.            │
└────────────────────┬────────────────────────┘
                     │ calls
┌────────────────────▼────────────────────────┐
│  Layer 4: System Under Test                 │
│  The actual production code.                │
└─────────────────────────────────────────────┘
```

### Key Properties

**Stability**: Acceptance tests know nothing about how the app works
internally. Even if the technical implementation changes entirely, the
specification remains valid. This is why LMAX (Farley's canonical example)
maintained 15–20K acceptance tests with few deletions over years of
development.

**Interface independence**: By swapping Protocol Drivers, the same
acceptance test suite can run against a web UI, a REST API, a CLI, and a
mobile interface. The test cases are written once.

**AI safety contract**: When using AI to generate implementation code, the
acceptance tests act as a contract. The AI can rewrite internals freely;
the tests determine whether the behaviour is correct.

---

## Four Layers Applied to AI Workflows

### The workflow

1. Write acceptance tests using the DSL (human-authored — this is the
   specification)
2. Give Claude Code the DSL interfaces + acceptance tests as context
3. Claude Code implements the Protocol Driver and System Under Test
4. Tests run — pass means done, fail means the AI missed the spec
5. Red-green-refactor cycle continues until all tests pass

### Why this works

The DSL is precise enough that Claude Code has an unambiguous contract.
The acceptance tests are immediately executable — there is no subjective
judgment about whether the implementation is "correct". The human's job
becomes writing the best possible specification, not reviewing every line
of generated code.

---

## On "Vibe Coding"

Farley is explicitly critical of AI-driven development without discipline.
His three objections:

1. **Lack of precision** in specifying requirements — the AI fills gaps
   with plausible-sounding but wrong assumptions
2. **No automated testing** to verify AI output — you can't manually
   review generated code at scale
3. **Difficulty of incremental change** — AI-generated codebases without
   tests become unmaintainable

His position: successful software is defined by its ability to be easily
changed. Vibe coding produces code that cannot be safely changed because
there is no verification mechanism.

---

## Python Implementation of the Four-Layer Model

### DSL Layer

In Python, the DSL is best expressed using `typing.Protocol` (PEP 544,
Python 3.8+). This provides structural subtyping — the driver implements
the protocol shape without explicit inheritance, matching the separation of
concerns intent of the model.

```python
# acceptance_tests/dsl/interfaces.py
from typing import Protocol

class UserDSL(Protocol):
    async def starts_with_new_account(self) -> None: ...
    async def has_completed_todo(self, description: str) -> None: ...
    async def confirm_next_turn(self, player: str) -> None: ...

class TodoDSL(Protocol):
    async def archive(self, description: str) -> None: ...
    def confirm_in_archive(self, description: str) -> None: ...
    def confirm_not_in_active(self, description: str) -> None: ...
```

**Why Protocol over ABC**: `Protocol` doesn't require the driver to
explicitly inherit from the DSL class, which keeps the driver free to
inherit from its own hierarchy (e.g., a Playwright page object). It also
works naturally with `mypy` for static verification that drivers correctly
implement the DSL contract.

### Protocol Driver Layer

```python
# acceptance_tests/drivers/http_driver.py
import httpx

class HttpTodoDSL:
    """Implements TodoDSL via HTTP API."""

    def __init__(self, base_url: str):
        self._client = httpx.AsyncClient(base_url=base_url)
        self._archived: list[str] = []

    async def archive(self, description: str) -> None:
        response = await self._client.post(
            "/todos/archive",
            json={"description": description}
        )
        response.raise_for_status()
        self._archived.append(description)

    def confirm_in_archive(self, description: str) -> None:
        assert description in self._archived, (
            f"Expected '{description}' in archive, got {self._archived}"
        )

    def confirm_not_in_active(self, description: str) -> None:
        # verified via state tracking or additional API call
        ...
```

### Acceptance Test Layer

**Option A: pytest with DSL (no Gherkin)**

```python
# acceptance_tests/test_todo_archive.py
import pytest
from acceptance_tests.dsl.interfaces import UserDSL, TodoDSL

@pytest.mark.acceptance
async def test_user_archives_completed_todo(
    user: UserDSL,
    todo: TodoDSL,
):
    # Given
    await user.starts_with_new_account()
    await user.has_completed_todo("Buy milk")

    # When
    await todo.archive("Buy milk")

    # Then
    todo.confirm_in_archive("Buy milk")
    todo.confirm_not_in_active("Buy milk")
```

**Option B: pytest-bdd with Gherkin feature files**

```gherkin
# features/todo_archive.feature
Feature: Todo archiving

  Scenario: User archives a completed todo
    Given the user has a new account
    And the user has completed a todo "Buy milk"
    When the todo "Buy milk" is archived
    Then "Buy milk" should be in the archive
    And "Buy milk" should not be in the active list
```

```python
# acceptance_tests/step_defs/test_todo_archive.py
from pytest_bdd import given, when, then, scenario
from acceptance_tests.dsl.interfaces import UserDSL, TodoDSL

@scenario("../features/todo_archive.feature",
          "User archives a completed todo")
def test_archive(): pass

@given("the user has a new account")
async def new_account(user: UserDSL):
    await user.starts_with_new_account()

@when('the todo "Buy milk" is archived')
async def archive_todo(todo: TodoDSL):
    await todo.archive("Buy milk")

@then('"Buy milk" should be in the archive')
def check_archive(todo: TodoDSL):
    todo.confirm_in_archive("Buy milk")
```

**Option C: behave (Gherkin-native, no pytest)**

```python
# features/steps/todo_steps.py
from behave import given, when, then

@given('the user has completed a todo "{description}"')
def step_completed_todo(context, description):
    context.user.has_completed_todo(description)

@when('the todo "{description}" is archived')
def step_archive(context, description):
    context.todo.archive(description)
```

### Framework Recommendation

| Approach | Best for |
|---|---|
| `pytest` + custom DSL | Teams that prefer Python-native, maximum flexibility |
| `pytest-bdd` | Teams wanting Gherkin files, pytest ecosystem |
| `behave` | Teams wanting pure Gherkin, non-developer readable |

For Claude Code workflows, **pytest + custom DSL** is recommended. It
integrates cleanly with the four-layer model, pytest fixtures map naturally
to DSL injection, and there is no Gherkin parsing overhead.

### Static Type Checking (Critical for Python)

Unlike TypeScript, Python Protocol mismatches don't fail at compile time —
they fail at runtime. To get compile-time equivalent enforcement, add mypy
or pyright to the verification step:

```bash
# mypy checks that drivers correctly implement the DSL protocols
mypy acceptance_tests/drivers/ --strict

# pyright is faster and has better Protocol support
pyright acceptance_tests/
```

This step must be part of the CI pipeline and the `/new-task` verification
phase. Without it, a driver that silently fails to implement the DSL will
produce confusing test failures rather than a clear "contract not met" error.

### Project Structure

```
project/
├── features/                    # Gherkin feature files (if using pytest-bdd/behave)
│   └── *.feature
├── acceptance_tests/
│   ├── dsl/
│   │   └── interfaces.py        # Protocol definitions — authoritative domain language
│   ├── drivers/
│   │   ├── http_driver.py       # HTTP Protocol Driver
│   │   ├── cli_driver.py        # CLI Protocol Driver
│   │   └── direct_driver.py     # In-process driver (for fast feedback)
│   ├── conftest.py              # pytest fixtures — driver injection
│   └── test_*.py                # Acceptance test specs
├── tests/
│   └── unit/                    # Unit tests (pytest, Kent Beck TDD style)
├── src/
│   └── *.py                     # Production code
├── dev-docs/
│   └── domain/
│       ├── DOMAIN.md            # Bounded context reasoning, business rules
│       └── GLOSSARY.md          # Human-readable terms → DSL mapping
└── pyproject.toml               # pytest config, mypy config, dependencies
```

### conftest.py — Driver Injection

```python
# acceptance_tests/conftest.py
import pytest
from acceptance_tests.drivers.http_driver import HttpUserDSL, HttpTodoDSL

@pytest.fixture
async def user() -> HttpUserDSL:
    driver = HttpUserDSL(base_url="http://localhost:8000")
    yield driver
    await driver.cleanup()

@pytest.fixture
async def todo(user: HttpUserDSL) -> HttpTodoDSL:
    return HttpTodoDSL(client=user.client)
```

To switch to a different driver (CLI, direct), only `conftest.py` changes.
The acceptance tests are untouched.

---

## Summary: Why This Matters for Claude Code

The four-layer model gives Claude Code a precise, verifiable contract for
every piece of implementation work:

- **DSL interfaces** tell Claude what operations must exist and what they
  are named in domain vocabulary
- **Acceptance tests** tell Claude what behaviour is required
- **Protocol drivers** are what Claude actually implements — bounded,
  testable, replaceable
- **The test suite** gives Claude an immediate feedback signal

This is the architecture that makes AI-generated code trustworthy at scale.
