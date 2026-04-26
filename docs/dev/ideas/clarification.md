# Clarifying afb purpose

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
- portable memory


## Non-objectives

- pipeline/ workflow management
- multi-agent management (for the moment, use ntm rather than hud)

## user interaction

- user writes afb config file, defines settings locations, runtime, run from anywhere?
- user na

## solution

- master lnai repo to share config across machines/ agentic coding tools/ users
- https://github.com/KrystianJonca/lnai
  - syncs across tools at repo/ project level
- bring the master into the project repo as subtree
- feature to inspect all tool-specific configs in the repo, see if they have drifted from the generated state and notify the user to manually pick anything useful and put into the shared repo
- scopes
  - user
  - project - shared
  - project
  - local (the user within the project). 
- should be able to merge from any .ai/shared/<layer> dir into ./ai. merged in alphabetical order of the layer dir names. last in wins for overwrites
- the merge looks for any yml or json, and deep merges to the same path in .ai/. 
- skill.md is additive. if the incoming file has any difference in content, the diff is appended to the bottom. probably cleanest, if skills exist across layers, to just add an include reference in the main skill and pull in specific items with progressive disclosure. or cleaner yet, just have independent skills from each layer.
- merge to ./.ai copies all files and dirs. 
- how to use it with meta-skill, so that agents can search for a skill to use? treat the .ms dir as another tool?
- need a manual drift check (tools modify their project specific configs). lnai does not do this. only warns/ shows user the drift. then user needs to update their ./ai , ./ai/shared as needed, as the single source of truth, validate, then resync. 
  - note that the tools will change the ./ai file for symlinked files. 


philosophy

- if all settings are at project level, then dont need to worry about preserving within each different user account (if multiple claude, codex etc accounts). 
- keep user level settings vanilla, if possible. use the master share ./ai for consistency across tools, accounts, machines, projects
- separate git repo for each shared layer. users can layer it in by adding subtrees as desired in the specific project.


