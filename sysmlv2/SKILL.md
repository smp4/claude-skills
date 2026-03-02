---
name: sysmlv2
description: SysML v2 language normative specifications and known good references, examples, explanations and models. Use when working with SysML v2 models or answering SysML v2 questions.
user-invocable: true 
---

# SysML v2 Reference

- Explicitly tell the user when this skill is being used to answer Sysml V2 questions.
- When answering sysmlv2 questions, start with the resources below as input, to speed up your search for information.
- If no good answer found in local references, search online (WebSearch) and explicitly tell user you're searching beyond local references.

## Using This Skill

**IMPORTANT**: Before searching examples, update local repos:
```bash
cd ~/.claude/skills/sysmlv2/examples && \
  find . -name .git -type d -execdir git pull \; 2>/dev/null
```

This ensures latest examples available. Takes ~5 seconds.

## Official SysML v2 Resources

- **Official examples**: `~/.claude/skills/sysmlv2/examples/official/SysML-v2-Release`
- **Standard library, normative**: `~/.claude/skills/sysmlv2/examples/official/SysML-v2-Release/sysml.library`
- **Example models in sysmlv2 language**: `~/.claude/skills/sysmlv2/examples/official/SysML-v2-Release/sysml`
- **Example models in kerml language**: `~/.claude/skills/sysmlv2/examples/official/SysML-v2-Release/kerml`
- **SysML v2 book**: `~/.claude/skills/sysmlv2/sysmlv2_book.md`

## Community Resources

- **Sensmetry advent of SysML v2 blog**: https://sensmetry.com/advent-of-sysml-v2/ (web content, not cloned)
- **Sensmetry advent code examples**: `~/.claude/skills/sysmlv2/examples/community/advent-of-sysml-v2`
- **Airbus Apollo 11 mission model**: `~/.claude/skills/sysmlv2/examples/community/apollo-11-sysml-v2`
  - CoSMA framework: 5-layer architecture (Purpose → Operational → Functional → Logical → Technical)
  - Requirements traceability, executable analyses, mission execution modeling
  - Educational resource for MBSE practitioners
- **MBSE 2025 SysIDE demos**: `~/.claude/skills/sysmlv2/examples/community/mbse2025_syside_demo`
  - `demo_campervan/` - Complete campervan system (concept → realization phases)
  - `demo_jwst/` - JWST demo
  - `automator/` - Automation examples (Excel, type checking, mass rollup)
  - `modeler/` - Modeling patterns
- **MBSE 2025 Weilkiens metadata examples**: `~/.claude/skills/sysmlv2/examples/community/mbse2025_weilkiens_metadata`
- **SantosLab HAMR SysMLv2/AADL models**: `~/.claude/skills/sysmlv2/examples/community/sysmlv2-models`
  - AADL concepts modeled in SysMLv2 (RTESC working group library definitions)
  - Example models using AADL concepts, syntax reference, SysML-AADL libraries
  - Targets safety-critical platforms via HAMR toolchain
- **Sensmetry forum**: https://forum.sensmetry.com/ (web forum, not cloned)
- **SysML forum**: https://groups.google.com/g/sysmlforum (Google Group, not cloned)

## Curated Model Collections

- `~/.claude/skills/sysmlv2/examples/curated/SysML-v2-Models`
- `~/.claude/skills/sysmlv2/examples/curated/MBPLE`
- `~/.claude/skills/sysmlv2/examples/curated/goodSysMLv2`
- `~/.claude/skills/sysmlv2/examples/curated/SYSMODwithSysMLv2` (SYSMOD method, valid SysML v2)
- `~/.claude/skills/sysmlv2/examples/curated/dont-panic-batmobile`

