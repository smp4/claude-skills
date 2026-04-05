# Uninstalling afb

## Standard uninstall

```bash
afb uninstall
```

This removes:
- All managed symlinks from each account's config dir (`skills/`, `hooks/`, `commands/`, `CLAUDE.md`, `statusline-command.sh`)
- Restores `settings.json` from `settings.json.original` for each account
- Removes the launchd plist or crontab entries created by `afb rate --daemon install`
- Removes `~/.local/bin/afb`

## Manual cleanup

If `afb uninstall` cannot run (e.g. `accounts.json` is gone):

### Remove symlinks

```bash
# For each account's claude_home (e.g. ~/.claude/.claudea):
rm ~/.claude/.claudea/hooks
rm ~/.claude/.claudea/commands
rm ~/.claude/.claudea/CLAUDE.md
rm ~/.claude/.claudea/statusline-command.sh
# Remove per-skill symlinks:
for s in ~/.claude/.claudea/skills/*/; do
  [[ -L "$s" ]] && rm "$s"
done
```

### Restore settings.json

```bash
cp ~/.claude/.claudea/settings.json.original ~/.claude/.claudea/settings.json
```

### Remove daemon

macOS:
```bash
launchctl bootout "gui/$(id -u)/com.afb.rate-monitor" 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.afb.rate-monitor.plist
```

Linux:
```bash
crontab -l | grep -v '# afb-managed' | crontab -
```

### Remove PATH symlink

```bash
rm -f ~/.local/bin/afb
```

### Remove generated files

```bash
# In the repo directory:
rm -f aliases.sh
```

`accounts.json` is gitignored — remove it manually if desired:
```bash
rm -f accounts.json
```

## Remove the repo

```bash
rm -rf ~/Projects/claude-skills   # or wherever you cloned it
```
