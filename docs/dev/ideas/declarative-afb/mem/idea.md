# Memory system

i want to add a memory system to hud. problems i want to solve:

- no semantic retrieval across sessions. claude re-reads files it already parsed in a prior session, burns token on identical content
- indiscriminate context loading - everything injected regardless of relevance
- no structural code understanding (rereads files already parsed) - repo map. list of files and their symbols. no persistent map of what files exist, what they export, or how they relate
- weak mistake-avoidance loops
- instruction adherence degrades with length. can follow 150-200 instructions reliably. claude.md, tool results, conversations compete.
- and others that i probably dont know about.

Actions to claude:

- Validate the problems I have listed above, and list other memory problems i may have mised.
- acknowledge my [constraints](#my-constraints.)
- I have researched some possible memory tools to help solve this (see [potential solutions](#potential-memory-additions)). This list is not complete. research [awesome lists and elsewhere](#awesome-claude-lists) if there are other memory systems i am missing.
- Propose an architecture for an ensemble of memory systems to use with hud and solve my memory problems. Provide a deep critique of your plan, noting advantages, disadvantages, risks and edge cases.
- recall hud will operate parallel pipelines of (sub-) agents working on same and different features in the same repo. the memory system needs to handle that.
- write your research, tradeoffs, critique, architecture, risk assessment to docs/dev/feat/mem/. 
- 

## my constraints

- only 1 or 2 claude pro accounts available. no API
- hosting local solutions, including databases and other models is OK. however hardware is limited to macbook air M2 with 16gb ram.
- Free open source solutions only
- i can create glue code, thats fine
- i do not want to create any solutions from scratch
- i want drop-in solutions (multiple OK). configuration is ok. DO NOT build from scratch.
- strongly prefer well-accepted solutions (many stars on github). 

## Potential memory additions

some solve the same problem, others solve orthogonal problems, others solve similar problems. 

- https://github.com/CaviraOSS/OpenMemory
- https://github.com/volcengine/OpenViking
- https://github.com/REMvisual/claude-handoff
- https://github.com/elvismdev/mem0-mcp-selfhosted
- https://github.com/doobidoo/mcp-memory-service
- https://github.com/letta-ai/letta-code
- https://github.com/Aider-AI/aider
- https://github.com/Dicklesworthstone/cass_memory_system
- https://github.com/Dicklesworthstone/coding_agent_session_search

## "awesome claude" lists

- https://github.com/ComposioHQ/awesome-claude-skills
- https://github.com/josix/awesome-claude-md
- https://github.com/hesreallyhim/awesome-claude-code
- https://github.com/mozilla-ai/cq

## other (non memory components) i want to include

i provide these so you can comment if you think there are overlaps with memory systems

- plan dependencies https://github.com/gastownhall/beads
  - with https://github.com/Dicklesworthstone/beads_viewer
- coordination https://github.com/Dicklesworthstone/mcp_agent_mail
- possible, not investigated: https://github.com/Dicklesworthstone/meta_skill