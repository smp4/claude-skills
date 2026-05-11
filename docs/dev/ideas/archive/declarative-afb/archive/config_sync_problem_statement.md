# Further notes on agent runtime configuration sync problem statement

## Problem

LLM providers constantly making rug-pulls. Need to be mobile as different models become more performant, better value etc.

## Objectives

- portability manager. sync settings, config between agent runtimes (cc, codex, oc, ...) and machines
  - hooks
  - commands
  - permissions
  - skills
  - mcp server config
  - runtime version pinning?
  - other dotfiles?
- operates at the agent runtime layer
- support cc, opencode, ntm/ acfs

## Non-objectives

- pipeline/ workflow management
- multi-agent management

## solution

- master repo to share config across machines/ agentic coding tools/ users
- how to sync master config repo to machines, projects, tools, users?
- how to bring the master into the project repo?
  -  as git subtree?
- feature: inspect all tool-specific configs in the repo, see if they have drifted from the generated state and notify the user to manually pick anything useful and put into the shared repo
- scopes
  - user
  - project - shared
  - project
  - local (the user within the project). 
- need a manual drift check (tools modify their project specific configs). lnai does not do this. only warns/ shows user the drift. then user needs to update their ./ai , ./ai/shared as needed, as the single source of truth, validate, then resync. 
  - note that the tools will change the ./ai file for symlinked files. 

### potential out of the box solution

- possible: https://github.com/KrystianJonca/lnai
  - syncs across tools at repo/ project level
- should be able to merge from any .ai/shared/<layer> dir into ./ai. merged in alphabetical order of the layer dir names. last in wins for overwrites
- the merge looks for any yml or json, and deep merges to the same path in .ai/. ?

- skill.md is additive. if the incoming file has any difference in content, the diff is appended to the bottom. probably cleanest, if skills exist across layers, to just add an include reference in the main skill and pull in specific items with progressive disclosure. or cleaner yet, just have independent skills from each layer.
- prefer symlinks to a single central file where possible, so that settings are shared instantly to all instances of all tools

## questions

- how to use it with meta-skill https://github.com/Dicklesworthstone/meta_skill, so that agents can search for a skill to use? treat the .ms dir as another tool?

## potential philosophy

- if all settings are at project level, then dont need to worry about preserving within each different user account (if multiple claude, codex etc accounts). 
- keep user level settings vanilla, if possible. use the master share ./ai for consistency across tools, accounts, machines, projects
- separate git repo for each shared layer. users can layer it in by adding subtrees as desired in the specific project.


