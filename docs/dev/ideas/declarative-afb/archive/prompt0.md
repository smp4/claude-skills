sketch an architecture combining the following existing functions and proposed tools/ solutions. 
challenge overlaps, YAGNIs. research deeply. critique the suggestions. always prefer existing tools over writing new libraries. DO NOT flatter me.

- agent runtimes: claude code, open code, codex
- model providers: claude code (native), open code (go/zen), open code (openrouter)
- Function: multi-agent/ runtime coordination
  - NTM https://github.com/Dicklesworthstone/ntm
  - Alternative suggestions welcome
- Function: define and police disciplined workflows, pipelines, recipes
  - NTM? 
- Function: settings/ config/ skills portability
  - LNAI https://github.com/KrystianJonca/lnai/tree/main to convert a single source of truth to config for multiple runtimes
  - git subtrees to sync each projects ./ai directory with a "master" config/ dotfiles repo
- Function: agent tasking
  - beads (beads rust) https://github.com/Dicklesworthstone/beads_rust
  - beads viewer https://github.com/Dicklesworthstone/beads_viewer_rust
- Function: agent coordination
  - mcp-agent-mail https://github.com/Dicklesworthstone/mcp_agent_mail
- Function: agent memory
  - CASS https://github.com/Dicklesworthstone/coding_agent_session_search
  - CASS memory https://github.com/Dicklesworthstone/cass_memory_system
- Function: skill mining and management
  - Meta-skill https://github.com/Dicklesworthstone/meta_skill
- Function: Deployment 
  - Ansible? is there a declarative alternative? Shall automate deploying the many tools to local or remote machines, with cross compatibility to linux and macos, and keeping the tools up to date, and teardown/ cleanup
- Function: automated handoff between context windows/ compaction management
  - No solution yet. Suggest solutions for context window management. Ideally we never get to compaction. we continuously record what we're working on, what didnt work, the task, next steps, then when copmaction is near, can clear contxt and start with a fresh session, inject the relevant history. sessions are ephemeral!
- Function: token efficient information search
  - websearch (Exa) https://github.com/mcp-research/exa-labs__exa-mcp-server
  - context7 (docs) https://github.com/upstash/context7
  - grep_app (GitHub search) https://vercel.com/blog/grep-a-million-github-repositories-via-mcp
- Function: token efficient codebase navigation and understanding
  - LSP 
  - AstGrep https://github.com/ast-grep/ast-grep

objectives:

- instant portability of all auxiliary tooling, config, settings, mcp servers, hooks, shared memory, skills, rules, permissions across runtimes and models
- ease of switching between LLMs, preferably with automated failover when usage limits are consumed
- agent configs live at project level, not in user-wide config for agent runtimes. 
- avoid single maintainer repos?
- TBC: risk avoidance. don't depend on single maintainer repos, single providers, single LLMs, single runtimes, ... use established tools. but this is difficult, since we are in the cambrian explosion period of AI application layer tooling
- state lives forever...somewhere. DB backups somewhere? ideally git repos. i dont want to look after database backups.
- the infra setup shall be user-agnostic. user customisation shall be imported from a personal user-specific repo. similarly, user-specific state shall be stored somewhere exportable. i shall be able to share this infra with others without having to share my personal settings.

Philosophy:

- Portability - between underlying LLMs, their providers, and runtimes.
- Extensible
- automated, frictionless. 
- sessions are ephemeral. context windows dont matter, all relevant info is recorded somewhere and auto-injected to the next relevant agent in the next relevant session
- agents are ephemeral. move between LLMs, agents as needed. inject prompts and context as needed to characterise the agent.
- agents are stateless
- declarative deployment. reproducible. automated, granular
- composable. everyone organises their workdesk differently. same for coding harness. probably too much friction to adopt any 1 other persons harness