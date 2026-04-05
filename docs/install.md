# Installing afb

`afb` (Agentic Flight Bag) is the CLI for managing Claude Code infrastructure: accounts, sessions, worktrees, and rate monitoring.

## Prerequisites

- bash
- python3 (already present on macOS and most Linux systems)
- git
- tmux (for `afb work` commands)

## Steps

### 1. Clone the repo

```bash
git clone <repo-url> ~/Projects/claude-skills
cd ~/Projects/claude-skills
```

### 2. Run the installer

```bash
./afb install
```

On first run with no `accounts.json`, `afb install` creates a default one pointing at `~/.claude`. Edit it before running if you want named accounts.

### 3. Source the generated aliases

```bash
# Add to ~/.zshrc or ~/.profile (run once):
echo "source $(pwd)/aliases.sh" >> ~/.zshrc

# Source in current terminal:
source aliases.sh
```

### 4. Verify

```bash
afb check
```

Exits 0 if everything is in sync.

## Multi-account setup

Edit `accounts.json` before running `afb install`:

```json
{
  "accounts": [
    { "name": "claudea", "claude_home": "~/.claude/.claudea", "default": true },
    { "name": "claudeb", "claude_home": "~/.claude/.claudeb" }
  ]
}
```

`accounts.json` is gitignored — each machine has its own.

## Staying in sync

With symlink mode, edits in `~/.claude/skills/` are edits to the repo. Pull to update:

```bash
git pull   # skills update immediately via symlinks
```

Restart Claude Code after pulling to reload skill metadata.

## Install options

```bash
afb install              # symlink mode (recommended)
afb install --copy       # copy instead of symlink (standalone snapshot)
afb install --force      # overwrite real files/dirs with symlinks
afb install --skip-diff  # skip settings.json diff prompt
```

## PATH

`afb install` creates `~/.local/bin/afb`. If `~/.local/bin` is not in your PATH, the installer will warn you and print the command to add it:

```bash
export PATH="${HOME}/.local/bin:${PATH}"
```
