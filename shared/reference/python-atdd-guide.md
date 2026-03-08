# Python ATDD Guide — Four-Layer Implementation

This guide covers the Python-specific implementation of the four-layer
ATDD model. For the language-agnostic model and TDD fundamentals, see
[tdd-guide.md](tdd-guide.md).

---

## Layer 2: DSL with `typing.Protocol`

Use `typing.Protocol` (PEP 544, Python 3.8+) for DSL interfaces.
Protocol provides structural subtyping — drivers implement the shape
without explicit inheritance, keeping concerns separated.

```python
# acceptance_tests/dsl/interfaces.py
from typing import Protocol

class UserDSL(Protocol):
    async def starts_with_new_account(self) -> None: ...
    async def has_completed_todo(self, description: str) -> None: ...

class TodoDSL(Protocol):
    async def archive(self, description: str) -> None: ...
    def confirm_in_archive(self, description: str) -> None: ...
    def confirm_not_in_active(self, description: str) -> None: ...
```

### Why Protocol over ABC

- Driver doesn't need to inherit from the DSL class
- Driver is free to inherit from its own hierarchy (e.g. Playwright page)
- Works naturally with `mypy` for static contract verification
- Matches the four-layer intent: DSL defines the shape, driver provides it

### Naming convention

DSL method names come from the domain glossary. Use snake_case
(Python convention) but preserve the domain term's meaning:

| Glossary term | DSL method |
|---|---|
| "Archive Todo" | `TodoDSL.archive_todo` |
| "Confirm Fulfilment" | `OrderDSL.confirm_fulfilment` |
| "Start New Account" | `UserDSL.starts_with_new_account` |

---

## Layer 3: Protocol Driver

Drivers implement the DSL for a specific interface. Each driver
translates domain operations into concrete system interactions.

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

### Multiple drivers, same tests

| Driver | Purpose |
|---|---|
| `http_driver.py` | Tests the HTTP API |
| `cli_driver.py` | Tests the CLI interface |
| `direct_driver.py` | In-process, no network — fast feedback |

Only `conftest.py` changes when switching drivers. Acceptance tests
are untouched.

---

## Layer 1: Acceptance Tests with pytest

```python
# acceptance_tests/test_todo_archive.py
import pytest

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

Use `@pytest.mark.acceptance` to separate acceptance tests from unit
tests. Run them independently:

```bash
pytest -m acceptance -v       # acceptance tests only
pytest -m "not acceptance" -v # unit tests only
pytest -v                     # everything
```

---

## Driver injection via conftest.py

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

To switch drivers, change the imports and fixture returns in
`conftest.py`. Nothing else changes.

---

## Static type checking (critical)

Python Protocol mismatches don't fail at compile time — they fail at
runtime with confusing errors. Add static verification:

```bash
# mypy — checks drivers implement DSL protocols
mypy acceptance_tests/drivers/ --strict

# pyright — faster, better Protocol support
pyright acceptance_tests/
```

This must be part of CI and the `/new-task` verification phase. Without
it, a driver that silently fails to implement the DSL produces confusing
test failures instead of a clear "contract not met" error.

---

## Project structure

```
project/
├── acceptance_tests/
│   ├── dsl/
│   │   └── interfaces.py        # Protocol definitions — THE domain language
│   ├── drivers/
│   │   ├── http_driver.py       # HTTP Protocol Driver
│   │   ├── cli_driver.py        # CLI Protocol Driver
│   │   └── direct_driver.py     # In-process driver (fast feedback)
│   ├── conftest.py              # pytest fixtures — driver injection
│   └── test_*.py                # Acceptance test specs
├── tests/
│   └── unit/                    # Unit tests (inner TDD loop)
├── src/
│   └── *.py                     # Production code
├── docs/
│   └── domain/
│       └── DOMAIN.md            # Business rules, glossary, examples
└── pyproject.toml               # pytest config, mypy config
```

---

## Framework comparison

| Approach | Best for |
|---|---|
| pytest + Protocol DSL | Claude Code workflows (recommended) |
| pytest-bdd | Teams wanting Gherkin files + pytest ecosystem |
| behave | Teams wanting pure Gherkin, non-developer readable |

**pytest + Protocol DSL is recommended for Claude Code.** It integrates
cleanly with the four-layer model, pytest fixtures map naturally to DSL
injection, and there is no Gherkin parsing overhead.
