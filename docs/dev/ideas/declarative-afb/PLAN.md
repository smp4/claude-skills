# AFB — Implementation Plan

> Date: 2026-04-26
> Spec: spec.md, architecture.md, domain.md (companions in this directory)
> Method: ATDD — one acceptance test per phase, starts failing, ends passing
> Repo: ~/Projects/afb (github.com/smp4/afb)

## Architecture Overview

Go CLI (cobra). Ports & Adapters. TOML manifest (`afb.toml`) drives everything. Core domain (`internal/domain/`) is pure logic — no external deps. Two ports: Git, ContainerRuntime. Adapters shell out to `git` and `podman`. Layer composition produces `.ai/`; sync command (default `lnai sync`) translates to runtime-native configs. Container generation via `text/template`. Lifecycle delegated to `podman-compose`.

See architecture.md for full details.

## Dogfooding Milestones

| After Phase | Capability |
|-------------|-----------|
| 3 | Running container with harness tools installed. Manual config |
| 5 | Config synced inside container via `afb sync` |
| 6 | Component versions tracked, lockfile, staleness detection |

## Go Project Structure

```
afb/
├── cmd/afb/
│   └── main.go                 # cobra root + subcommands, wiring
├── internal/
│   ├── domain/                 # pure logic, no external deps
│   │   ├── manifest/           # parsing, validation, variable expansion
│   │   ├── lock/               # lockfile read/write/check
│   │   ├── compose/            # layer composition, deep merge
│   │   └── generate/           # Containerfile + compose.yaml templates
│   ├── ports/                  # interface definitions
│   │   ├── git.go
│   │   └── runtime.go
│   ├── adapters/               # external tool implementations
│   │   ├── gitcli/
│   │   └── podman/
│   ├── doctor/                 # diagnostics
│   ├── diff/                   # drift detection
│   └── runner/                 # script + command execution
├── test/
│   └── acceptance/             # ATDD tests (//go:build acceptance)
├── testdata/                   # fixtures
├── docs/
│   └── developing.md
├── .github/workflows/ci.yml
├── .lefthook.yml
├── .golangci.yml
├── justfile
├── CHANGELOG.md
├── go.mod
└── go.sum
```

## Acceptance Test Convention

All acceptance tests in `test/acceptance/`, build-tagged `//go:build acceptance`. Each phase gets one test function: `TestPhaseN_Description`. Tests exercise the compiled `afb` binary as a black box via `os/exec`.

Unit tests (TDD within each phase) live alongside code in `internal/` packages, no build tags, no external deps for `domain/` packages.

Integration tests tagged `//go:build integration` (require git). E2E tests tagged `//go:build e2e` (require podman).

---

## Phase 0: Project Scaffolding

**Goal**: Buildable Go project with CI, hooks, tooling, and docs.

**Acceptance test**: `TestPhase0_Version` — build `afb` binary, run `afb version`, assert output contains semver string `0.1.0-dev`.

### Unit 0.1: Go Module + Cobra Skeleton

- **Delivers**: `afb` binary with `version` and `help` subcommands
- **Files**: `go.mod`, `cmd/afb/main.go`, `cmd/afb/version.go`
- **Tests first**: acceptance test above
- **Implementation**:
  - `go mod init github.com/smp4/afb`
  - cobra root command + `version` subcommand
  - Version string via `-ldflags` build tag, fallback to `0.1.0-dev`
  - zerolog configured: structured JSON to stderr, `AFB_LOG_LEVEL` env var
- **Deps**: `github.com/spf13/cobra`, `github.com/rs/zerolog`

### Unit 0.2: CI Workflow

- **Delivers**: GitHub Actions pipeline
- **Files**: `.github/workflows/ci.yml`
- **Implementation**:
  - Jobs: `unit` (go test ./...), `lint` (golangci-lint), `format` (gofmt -d)
  - Go 1.23, ubuntu-latest
  - Trigger: push + PR to main
  - Acceptance tests in separate job (`go test -tags acceptance ./test/acceptance/...`)
  - Integration job: `go test -tags integration ./...` (git pre-installed)
  - E2e job: `go test -tags e2e ./...` (podman pre-installed, podman-compose via `webgtx/setup-podman-compose@v1`)
  - E2e runs on merge to main only (slow)

### Unit 0.3: Lefthook

- **Delivers**: Pre-commit and commit-msg hooks
- **Files**: `.lefthook.yml`
- **Implementation**:
  - `pre-commit`: `golangci-lint run`, `gofmt -l .` (fail if output), `go test ./internal/domain/...`
  - `commit-msg`: shell regex check for conventional commit format (`^(feat|fix|refactor|docs|test|chore|ci|build)(\(.+\))?: .+`)
  - Parallel where possible

### Unit 0.4: Justfile

- **Delivers**: Common dev commands
- **Files**: `justfile`
- **Implementation**:
  ```
  default: test
  build: go build ./cmd/afb
  test: go test ./...
  test-acceptance: go test -tags acceptance ./test/acceptance/...
  test-integration: go test -tags integration ./...
  test-e2e: go test -tags e2e ./...
  lint: golangci-lint run
  fmt: gofmt -w .
  changelog: # open CHANGELOG.md in $EDITOR
  ```

### Unit 0.5: Linting Config

- **Delivers**: golangci-lint configuration
- **Files**: `.golangci.yml`
- **Implementation**: Enable `errcheck`, `govet`, `staticcheck`, `unused`, `ineffassign`, `gosimple`. Disable noisy linters. Go 1.23.

### Unit 0.6: Changelog + Docs

- **Delivers**: CHANGELOG.md skeleton, docs/developing.md
- **Files**: `CHANGELOG.md`, `docs/developing.md`
- **Implementation**:
  - CHANGELOG.md: keepachangelog.com format, `[Unreleased]` section
  - docs/developing.md: prerequisites (Go 1.23, lefthook, just, golangci-lint, hadolint, podman, podman-compose), setup steps, justfile command reference, test tiers, conventional commit format, changelog workflow

### Unit 0.7: Repo Boilerplate

- **Delivers**: Standard repo files
- **Files**: `.gitignore`, `.editorconfig`, `LICENSE`
- **Implementation**:
  - .gitignore: Go binary, vendor/, .afb/layers/, .afb/generated/, .ai/, afb.local.toml, OS files
  - .editorconfig: utf-8, lf, 4-space tabs for Go (or tabs — Go standard is tabs)
  - LICENSE: MIT

**Traces to**: NFR3 (single binary), NFR5 (testable), NFR6 (portable), IMR-2 through IMR-8

---

## Phase 1: Manifest Parsing & Validation

**Goal**: Parse `afb.toml` into Go struct, validate schema, reject invalid manifests.

**Acceptance test**: `TestPhase1_Validate`
- `afb validate testdata/valid/afb.toml` → exit 0, stdout "valid"
- `afb validate testdata/invalid-dup-priority/afb.toml` → exit non-zero, stderr contains "duplicate priority"
- `afb validate testdata/invalid-missing-install/afb.toml` → exit non-zero, stderr contains "missing required field: install"

### Unit 1.1: Manifest Struct + TOML Parsing

- **Delivers**: `manifest.Load(path) (*Manifest, error)` — parses afb.toml to typed struct
- **Files**: `internal/domain/manifest/manifest.go`, `manifest_test.go`
- **Tests first**:
  - `TestLoad_ValidManifest` — round-trip parse of full manifest from testdata
  - `TestLoad_MinimalManifest` — only required fields
  - `TestLoad_InvalidTOML` — malformed TOML → error
- **Implementation**: Use `BurntSushi/toml`. Struct tags. All fields from architecture.md data model.
- **Deps**: `github.com/BurntSushi/toml`

### Unit 1.2: Validation Rules

- **Delivers**: `manifest.Validate(m *Manifest) []error`
- **Files**: `internal/domain/manifest/validate.go`, `validate_test.go`
- **Tests first**:
  - `TestValidate_SchemaVersionMissing` → error
  - `TestValidate_SchemaVersionUnsupported` → error with message
  - `TestValidate_DuplicateLayerPriority` → error naming both layers
  - `TestValidate_ComponentMissingInstall` → error naming component
  - `TestValidate_LayerMissingSource` → error naming layer
  - `TestValidate_RuntimeNotPodman` → error (v1 podman-only)
  - `TestValidate_ValidManifest` → no errors
- **Implementation**: Iterate components, layers, check invariants. Return all errors (not first-fail).

### Unit 1.3: Local Manifest Merge

- **Delivers**: `manifest.MergeLocal(base, local *Manifest) *Manifest` — shallow merge
- **Files**: `internal/domain/manifest/local.go`, `local_test.go`
- **Tests first**:
  - `TestMergeLocal_OverridesTopLevelKey` — local [container] replaces base [container]
  - `TestMergeLocal_PreservesUnsetKeys` — keys not in local preserved from base
  - `TestMergeLocal_NoLocalFile` — returns base unchanged
- **Implementation**: Shallow merge — top-level TOML tables in local replace same in base.

### Unit 1.4: Variable Expansion

- **Delivers**: `manifest.ExpandVars(m *Manifest, projectRoot string)` — expands `${version_spec}`, `${scripts_dir}`, `${project_root}`
- **Files**: `internal/domain/manifest/expand.go`, `expand_test.go`
- **Tests first**:
  - `TestExpandVars_VersionSpec` — `${version_spec}` in install → replaced
  - `TestExpandVars_ScriptsDir` — `${scripts_dir}` → value from settings
  - `TestExpandVars_ProjectRoot` — `${project_root}` → absolute path
  - `TestExpandVars_UnknownVar` — `${unknown}` → left as-is (no error)
- **Implementation**: Simple `strings.ReplaceAll` per variable. No template engine.

### Unit 1.5: `afb validate` Command

- **Delivers**: Cobra subcommand wiring
- **Files**: `cmd/afb/validate.go`
- **Implementation**: Load manifest, run validation, print errors, exit with code 2 on validation error. Accept optional path argument (default: `afb.toml` in cwd).

**Traces to**: FR1, FR9, NFR2

---

## Phase 2: Container Generation

**Goal**: Generate Containerfile + compose.yaml from manifest. Build image.

**Acceptance test**: `TestPhase2_Build`
- Create test manifest in temp dir
- `afb build --generate-only` → generates `.afb/generated/Containerfile` + `compose.yaml`
- Assert Containerfile contains expected FROM, component install commands
- Assert compose.yaml contains expected services, networks, volumes
- Validate: `hadolint .afb/generated/Containerfile` exits 0
- Validate: `podman-compose -f .afb/generated/compose.yaml config --quiet` exits 0
- (E2e variant): `afb build` (no flag) → image built, `podman image inspect` succeeds

### Unit 2.1: Containerfile Generation

- **Delivers**: `generate.Containerfile(m *Manifest, w io.Writer) error`
- **Files**: `internal/domain/generate/containerfile.go`, `containerfile.tmpl`, `containerfile_test.go`
- **Tests first**:
  - `TestContainerfile_BaseImage` — FROM matches `[container].base_image`
  - `TestContainerfile_ComponentInstalls` — one RUN per enabled component
  - `TestContainerfile_DisabledComponentSkipped` — enabled=false → no RUN
  - `TestContainerfile_ExtraPackages` — apt-get install includes extras
  - `TestContainerfile_ExtraRun` — extra commands present after component installs
  - `TestContainerfile_BuildArgs` — ARG declarations present
  - `TestContainerfile_Entrypoint` — ENTRYPOINT matches config
- **Implementation**: `text/template` with `.tmpl` file. Template produces output from architecture.md §Generated Containerfile. At this phase, NO `RUN afb sync` line — added in Phase 5.
- **Note**: Containerfile at this phase installs components and clones project. Sync step added when sync exists.

### Unit 2.2: Compose File Generation

- **Delivers**: `generate.ComposeFile(m *Manifest, w io.Writer) error`
- **Files**: `internal/domain/generate/composefile.go`, `composefile.tmpl`, `composefile_test.go`
- **Tests first**:
  - `TestComposeFile_ServiceName` — derived from project dir
  - `TestComposeFile_BuildContext` — correct relative paths
  - `TestComposeFile_ExternalNetwork` — external MCP services get `external: true` network
  - `TestComposeFile_NamedVolumes` — volumes declared
  - `TestComposeFile_StdinTTY` — `stdin_open` and `tty` present
  - `TestComposeFile_ProjectName` — compose project naming
- **Implementation**: `text/template`. Output matches architecture.md §Generated Compose File. Only features from Compose Spec Compliance table.

### Unit 2.3: ContainerRuntime Port + Podman Adapter (Build)

- **Delivers**: `ContainerRuntime` interface, `PodmanRuntime.Build()`
- **Files**: `internal/ports/runtime.go`, `internal/adapters/podman/runtime.go`, `podman_test.go`
- **Tests first** (integration, tagged):
  - `TestPodmanBuild_ValidContainerfile` — builds image, returns image ID
- **Implementation**: Shell out to `podman build`. Tag: `afb-{dirname}:latest`.

### Unit 2.4: `afb build` Command

- **Delivers**: Cobra subcommand
- **Files**: `cmd/afb/build.go`
- **Implementation**: Load manifest → generate Containerfile + compose.yaml to `.afb/generated/` → create `.afb/generated/.env`. If `--generate-only`: stop here (exit 0). Otherwise: invoke `podman-compose build`. `--strict` flag. Exit codes per spec.
- **Note**: `--generate-only` enables validation (hadolint, podman-compose config) without container runtime. Used by unit-level CI jobs.

**Traces to**: FR6, FR10, NFR2

---

## Phase 3: Container Lifecycle

**Goal**: Start, stop, and rebuild containers.

**Acceptance test**: `TestPhase3_Lifecycle` (tagged `//go:build e2e`)
- `afb build` in test project
- `afb up` → assert container running (`podman ps` shows it)
- `afb down` → assert container stopped
- `afb rebuild` → assert container replaced (new container ID)

### Unit 3.1: PodmanRuntime ComposeUp/ComposeDown

- **Delivers**: `PodmanRuntime.ComposeUp()`, `.ComposeDown()`
- **Files**: `internal/adapters/podman/runtime.go` (extend)
- **Tests first** (e2e):
  - `TestPodmanComposeUp_StartsContainer`
  - `TestPodmanComposeDown_StopsContainer`
- **Implementation**: Shell out to `podman-compose up -d` / `podman-compose down`. Accept `--project` flag for project name override.

### Unit 3.2: Lifecycle Commands

- **Delivers**: `afb up`, `afb down`, `afb rebuild` cobra commands
- **Files**: `cmd/afb/up.go`, `cmd/afb/down.go`, `cmd/afb/rebuild.go`
- **Implementation**:
  - `up`: load manifest, compose up, `--project` flag
  - `down`: load manifest, compose down, `--project` flag
  - `rebuild`: build → down → up (sequential)

**Traces to**: FR6, FR10

### 🎯 Dogfood Milestone 1

After Phase 3: create a real `afb.toml` for a project, `afb build && afb up`, get a running container with claude-code installed. Config is manual at this point.

---

## Phase 4: Layer Composition

**Goal**: Compose layers by priority into `.ai/` with correct merge semantics.

**Acceptance test**: `TestPhase4_Compose`
- Set up 3 layer dirs in temp: `base/` (priority 10), `team/` (priority 20), project config
- base has `settings.yaml` with `{a: 1, b: 2}`, `AGENTS.md` with "base content"
- team has `settings.yaml` with `{b: 3, c: 4}`, `rules/no-yolo.md` with "team rule"
- project has `settings.yaml` with `{c: 5}`, `AGENTS.md` with "project content"
- Run composition
- Assert `.ai/settings.yaml` = `{a: 1, b: 3, c: 5}` (deep merge, higher priority wins)
- Assert `.ai/AGENTS.md` = "project content" (overwrite, highest priority wins)
- Assert `.ai/rules/no-yolo.md` = "team rule" (propagated from team layer)
- Assert `.ai/.ai-format-version` = "1"

### Unit 4.1: Git Port + GitCLI Adapter

- **Delivers**: `Git` interface + `GitCLI` implementation
- **Files**: `internal/ports/git.go`, `internal/adapters/gitcli/git.go`, `gitcli_test.go`
- **Tests first** (integration):
  - `TestGitCLI_Clone` — clone test repo to temp dir
  - `TestGitCLI_ResolveRef` — returns commit hash
  - `TestGitCLI_Pull` — pull updates
- **Implementation**: Shell out to `git clone`, `git pull`, `git rev-parse HEAD`.

### Unit 4.2: mergo Characterization Tests

- **Delivers**: Verified understanding of mergo behavior, especially zero-value edge cases
- **Files**: `internal/domain/compose/mergo_test.go`
- **Tests first** (these ARE the deliverable):
  - `TestMergo_NilSrcPopulatedDst` — dst preserved
  - `TestMergo_PopulatedSrcNilDst` — src wins
  - `TestMergo_ArrayReplace` — incoming array replaces existing
  - `TestMergo_EmptyStringSrcNonEmptyDst` — **incoming wins** (verify)
  - `TestMergo_ZeroIntSrcNonZeroDst` — **incoming wins** (verify)
  - `TestMergo_FalseBoolSrcTrueDst` — **incoming wins** (verify)
  - `TestMergo_EmptySliceSrcPopulatedDst` — incoming wins
  - `TestMergo_MixedTypeLeafConflict` — incoming wins
  - `TestMergo_NestedMapMerge` — recursive merge, incoming wins at leaf
- **Implementation**: If `WithOverwriteWithEmptyValue` unreliable, implement custom `mergo.WithTransformers`.
- **Deps**: `dario.cat/mergo@v1.0.2`

### Unit 4.3: Deep Merge Implementation

- **Delivers**: `compose.DeepMerge(dst, src map[string]any) error`
- **Files**: `internal/domain/compose/merge.go`, `merge_test.go`
- **Tests first**:
  - `TestDeepMerge_YAMLFiles` — merge two parsed YAML maps
  - `TestDeepMerge_TOMLFiles` — merge two parsed TOML maps
  - `TestDeepMerge_JSONFiles` — merge two parsed JSON maps
  - `TestDeepMerge_IncomingWinsAtLeaf`
  - `TestDeepMerge_ArraysReplace`
  - `TestDeepMerge_AbsentKeyPreserved`
- **Implementation**: Wrapper around mergo with correct flags. Parse file by extension → `map[string]any` → merge → serialize back.
- **Deps**: `gopkg.in/yaml.v3`, `encoding/json`

### Unit 4.4: Compose Algorithm

- **Delivers**: `compose.Run(layers []Layer, projectDir string, outputDir string) error`
- **Files**: `internal/domain/compose/compose.go`, `compose_test.go`
- **Tests first**:
  - `TestCompose_PriorityOrdering` — higher priority wins
  - `TestCompose_StructuredFileMerge` — YAML/JSON/TOML deep-merged
  - `TestCompose_UnstructuredFileOverwrite` — MD/txt overwritten
  - `TestCompose_ProjectConfigHighestPriority` — .afb/project/ wins over all layers
  - `TestCompose_AtomicReplace` — old .ai/ fully replaced
  - `TestCompose_FormatVersion` — .ai-format-version = "1" written
  - `TestCompose_OverwriteStrategy` — layer with strategy=overwrite replaces all files
- **Implementation**: Algorithm from architecture.md §Layer Composition Algorithm. Temp dir → compose → atomic rename.

**Traces to**: FR2, NFR1

---

## Phase 5: Sync Orchestration

**Goal**: Full sync pipeline: pull → compose → validate → sync command → lockfile. Idempotent.

**Acceptance test**: `TestPhase5_Sync`
- Project dir with manifest, layers (local dirs, not git for test simplicity), mock sync command (script that copies .ai/ content to .claude/)
- `afb sync` → .ai/ populated, sync command ran, afb.lock written with layer hashes
- Modify nothing. `afb sync` again → .ai/ byte-identical (idempotency check via checksum)
- Assert lockfile has `[layers.X].ref_resolved`, `[components.Y].install_ok`

### Unit 5.1: Lockfile Read/Write

- **Delivers**: `lock.Load(path) (*Lockfile, error)`, `lock.Write(lf *Lockfile, path string) error`
- **Files**: `internal/domain/lock/lock.go`, `lock_test.go`
- **Tests first**:
  - `TestLockfile_RoundTrip` — write then read, struct equality
  - `TestLockfile_ComponentEntry` — version, timestamp, install_ok
  - `TestLockfile_LayerEntry` — ref_requested, ref_resolved, pulled_at
  - `TestLockfile_ContainerEntry` — image_id, built_at
- **Implementation**: TOML serialization via BurntSushi/toml. Comment header with generation timestamp.

### Unit 5.2: Sync Orchestrator

- **Delivers**: `sync.Run(m *Manifest, git ports.Git, opts SyncOpts) error`
- **Files**: `internal/sync/sync.go`, `sync_test.go`
- **Tests first** (integration):
  - `TestSync_FullPipeline` — layers cloned, composed, validated, sync cmd run, lockfile written
  - `TestSync_ConfigOnly` — `--config` flag skips components
  - `TestSync_ComponentsOnly` — `--components` flag skips composition
  - `TestSync_ValidationFailure` — validation error → sync cmd NOT run, exit code 2
  - `TestSync_SyncCmdFailure` — sync cmd fails → exit code 3
  - `TestSync_Idempotent` — two runs, identical .ai/
- **Implementation**: Orchestrate steps from architecture.md §afb sync (detailed). Shell out sync command via `os/exec`. Exit codes: 0 success, 1 composition, 2 validation, 3 sync cmd, 4 component install.

### Unit 5.3: `afb sync` Command

- **Delivers**: Cobra subcommand with `--config`, `--components`, `--pull` flags
- **Files**: `cmd/afb/sync.go`
- **Implementation**: Wire manifest + git adapter + sync orchestrator. Log summary.

### Unit 5.4: Update Containerfile Template

- **Delivers**: Add `RUN afb sync` step to Containerfile template
- **Files**: `internal/domain/generate/containerfile.tmpl` (update)
- **Tests**: Update `TestContainerfile_*` to assert `RUN afb sync` present
- **Implementation**: Add sync step after project clone, before runtime ENV.

**Traces to**: FR1, FR2, FR9, NFR1, NFR2

### 🎯 Dogfood Milestone 2

After Phase 5: `afb sync && afb build && afb up` gives a container with composed config, synced to runtime-native formats. Full declarative workflow operational.

---

## Phase 6: Lockfile & Component Management

**Goal**: Version resolution, staleness detection, install failure handling.

**Acceptance test**: `TestPhase6_LockCheck`
- `afb sync` in test project → lockfile written
- `afb lock --check` → exit 0 (fresh)
- Edit afb.toml: change a component's `version_spec`
- `afb lock --check` → exit non-zero (stale)
- `afb lock` → lockfile updated, new version resolved
- `afb lock --check` → exit 0 again

### Unit 6.1: Version Hook Execution

- **Delivers**: Run component's `version` command, capture stdout
- **Files**: `internal/runner/version.go`, `version_test.go`
- **Tests first**:
  - `TestVersionHook_CapturesStdout` — output stored
  - `TestVersionHook_NoHook` — component without version → `installed_version` empty
  - `TestVersionHook_FailingHook` — exit non-zero → logged, install_ok still based on install

### Unit 6.2: Staleness Check

- **Delivers**: `lock.Check(manifest *Manifest, lockfile *Lockfile) (bool, []string)`
- **Files**: `internal/domain/lock/check.go`, `check_test.go`
- **Tests first**:
  - `TestCheck_Fresh` — manifest matches lockfile → true, no reasons
  - `TestCheck_VersionDrift` — version_spec changed → false, reason includes component name
  - `TestCheck_LayerRefChanged` — layer ref changed → false
  - `TestCheck_NewComponent` — component added → false
  - `TestCheck_RemovedComponent` — component removed → false

### Unit 6.3: Install Failure Handling

- **Delivers**: Log error + continue (default), abort (--strict)
- **Files**: extend `internal/sync/sync.go`
- **Tests first**:
  - `TestInstallFailure_LogAndContinue` — other components still installed
  - `TestInstallFailure_StrictAborts` — first failure stops all
  - `TestInstallFailure_RecordedInLockfile` — `install_ok = false`

### Unit 6.4: `afb lock` Commands

- **Delivers**: `afb lock`, `afb lock --check`
- **Files**: `cmd/afb/lock.go`

**Traces to**: FR1, NFR1, NFR2

---

## Phase 7: Init

**Goal**: Scaffold new project from scratch or template.

**Acceptance test**: `TestPhase7_Init`
- Empty temp dir
- `afb init` → assert `afb.toml` exists with `schema_version = 1`, `.afb/project/` dir exists, `.gitignore` has expected entries
- Separate empty temp dir
- `afb init --template <path-to-test-template>` → assert manifest has `[template]` section with source + ref_resolved

### Unit 7.1: Scaffold Generation

- **Delivers**: Create minimal afb.toml + directory structure
- **Files**: `internal/init/scaffold.go`, `scaffold_test.go`
- **Tests first**:
  - `TestScaffold_CreatesManifest` — afb.toml with schema_version, empty sections
  - `TestScaffold_CreatesProjectDir` — .afb/project/ exists
  - `TestScaffold_AddsGitignore` — entries for .ai/, .afb/layers/, etc.
  - `TestScaffold_NoOverwrite` — existing afb.toml → error

### Unit 7.2: Template Support

- **Delivers**: Clone template, copy to manifest, record source
- **Files**: `internal/init/template.go`, `template_test.go`
- **Tests first**:
  - `TestTemplate_LocalPath` — copies from local dir
  - `TestTemplate_RecordsSource` — [template] section populated
  - `TestTemplate_ResolvesRef` — mutable ref → commit hash recorded
- **Implementation**: Parse template source format: `git@...//path@ref` or local path.

### Unit 7.3: `afb init` Command

- **Delivers**: Cobra subcommand with `--template` flag
- **Files**: `cmd/afb/init.go`

**Traces to**: FR6 (fresh machine setup)

---

## Phase 8: Drift & Doctor

**Goal**: Detect config drift. Context-aware diagnostics.

**Acceptance test**: `TestPhase8_Doctor`
- `afb sync` in test project (clean state)
- `afb doctor` → exit 0, reports all checks clean
- Modify a file in `.ai/` manually
- `afb doctor` → exit non-zero, reports composition drift for modified file
- Restore file. Edit afb.toml to change version.
- `afb doctor` → reports lockfile stale

### Unit 8.1: Composition Diff

- **Delivers**: `diff.Composition(manifest, aiDir string) ([]FileDiff, error)`
- **Files**: `internal/diff/diff.go`, `diff_test.go`
- **Tests first**:
  - `TestCompositionDiff_Clean` — no differences
  - `TestCompositionDiff_ModifiedFile` — reports changed file
  - `TestCompositionDiff_ExtraFile` — reports unexpected file in .ai/
  - `TestCompositionDiff_MissingFile` — reports missing expected file

### Unit 8.2: Runtime Diff

- **Delivers**: `diff.Runtime(manifest, syncCmd string) ([]FileDiff, error)`
- **Files**: `internal/diff/runtime.go`, `runtime_test.go`
- **Tests first** (integration):
  - `TestRuntimeDiff_Clean` — no drift
  - `TestRuntimeDiff_ModifiedRuntimeConfig` — reports changed .claude/ file
- **Implementation**: Compose to temp dir → run sync command in temp HOME → diff output against actual runtime dirs.

### Unit 8.3: Doctor Orchestrator

- **Delivers**: `doctor.Run(manifest, cwd string) (*Report, error)`
- **Files**: `internal/doctor/doctor.go`, `doctor_test.go`
- **Tests first**:
  - `TestDoctor_ProjectContext_AllClean` — lockfile fresh, no drift, components healthy
  - `TestDoctor_ProjectContext_LockfileStale` — reports issue
  - `TestDoctor_ProjectContext_CompositionDrift` — reports drift
  - `TestDoctor_ProjectContext_TemplateDrift` — reports upstream template moved
  - `TestDoctor_ProjectContext_ComponentDoctorFails` — reports unhealthy component
  - `TestDoctor_HostContext_Prerequisites` — checks git, podman installed
- **Implementation**: Traverse upward from cwd to find topmost afb.toml. Project context: lockfile check + composition diff + runtime diff + template check + component doctors. Host context: binary availability checks.

### Unit 8.4: `afb diff` + `afb doctor` Commands

- **Delivers**: Cobra subcommands
- **Files**: `cmd/afb/diff.go`, `cmd/afb/doctor.go`

**Traces to**: FR3, FR7, NFR2

---

## Phase 9: Runner & Push

**Goal**: Execute scripts, component commands, push layer changes.

**Acceptance test**: `TestPhase9_RunAndPush`
- Create test script `.afb/scripts/hello.sh` that writes "hello" to a file
- `afb run hello` → file created with "hello"
- Create manifest with component having `[commands] doctor = "echo healthy"`
- `afb run mycomp.doctor` → stdout contains "healthy"
- (Push tested with local bare git repo)
- Clone layer from local bare repo, modify a file
- `afb push mylayer` → bare repo has the change

### Unit 9.1: Script Runner

- **Delivers**: `runner.Script(scriptsDir, name string) error`
- **Files**: `internal/runner/runner.go`, `runner_test.go`
- **Tests first**:
  - `TestRunScript_Executes` — script runs, side effect observed
  - `TestRunScript_NotFound` — error with clear message
  - `TestRunScript_NonZeroExit` — error propagated
- **Implementation**: Resolve path in scripts_dir, `os/exec`. Inherit env. Expand variables.

### Unit 9.2: Component Command Runner

- **Delivers**: `runner.ComponentCommand(manifest, target string) error`
- **Files**: extend `internal/runner/runner.go`
- **Tests first**:
  - `TestRunComponentCmd_Executes` — `comp.cmd` format parsed, command run
  - `TestRunComponentCmd_VariableExpansion` — `${project_root}` expanded
  - `TestRunComponentCmd_CommandNotFound` — error: "component 'x' has no command 'y'"
  - `TestRunComponentCmd_ComponentNotFound` — error: "unknown component 'x'"

### Unit 9.3: Layer Push

- **Delivers**: `push.Layer(layerDir string, git ports.Git) error`
- **Files**: `internal/push/push.go`, `push_test.go`
- **Tests first** (integration):
  - `TestPushLayer_PushesToRemote` — changes visible in bare repo
  - `TestPushLayer_AllLayers` — push all layer dirs
- **Implementation**: `git -C <layer-dir> push` via Git port.

### Unit 9.4: `afb run` + `afb push` Commands

- **Delivers**: Cobra subcommands
- **Files**: `cmd/afb/run.go`, `cmd/afb/push.go`
- **Implementation**: `afb run <name>` dispatches: if contains `.`, treat as `component.command`; otherwise, treat as script name.

**Traces to**: FR4, FR5, FR8

---

## Dependency Graph

```
Phase 0 ──► Phase 1 ──► Phase 2 ──► Phase 3  [dogfood 1]
                  │
                  ├────► Phase 4 ──► Phase 5  [dogfood 2]
                  │                     │
                  │                     ├──► Phase 6
                  │                     └──► Phase 8
                  │
                  ├────► Phase 7
                  └────► Phase 9
```

Phases 7, 8, 9 can be parallelised after their dependencies are met.

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| mergo zero-value override bug | Medium | High | Characterization tests in Phase 4 before any composition logic. Custom transformer if needed |
| podman-compose feature gaps | Low-Medium | Medium | Use only safe feature subset (architecture.md table). Validate in CI |
| LNAI breaking changes | Medium | Medium | Pin version. Sync command configurable via `[sync].command` |
| Containerfile without `afb sync` (Phase 2-3) | — | Low | Known limitation until Phase 5. Document in Phase 2 AT |
| E2e tests slow CI | Medium | Low | Run e2e only on merge to main. Unit tests on every push. `--generate-only` enables validation without podman |
| lefthook new to user | Low | Low | Simple config, documented in developing.md |

## Fitness Functions

| Property | Check | Automation |
|---|---|---|
| Composition idempotency | `afb sync` twice, diff .ai/ | CI job (Phase 5+) |
| Containerfile validity | hadolint on generated Containerfile | CI job (Phase 2+) |
| Compose spec validity | `podman-compose config --quiet` | CI job (Phase 2+) |
| Unit test tier isolation | `go test ./internal/domain/...` — no git/podman/network | CI: separate job, no tools installed |
| Conventional commits | commit-msg hook regex | lefthook |
| Lint clean | golangci-lint | lefthook pre-commit + CI |

## Decision Reversibility

| Decision | Reversibility | Notes |
|---|---|---|
| TOML manifest format | Irreversible | All config depends on it (ADR-024) |
| Array replace as merge default | Expensive | All layer content assumes this (ADR-006) |
| Integer priority ordering | Expensive | All manifests assume numeric order (ADR-009) |
| Podman only (v1) | Cheap | ContainerRuntime port exists for Docker (ADR-015) |
| lefthook for hooks | Cheap | Swap for any git hook manager |
| mergo for deep merge | Moderate | Custom transformer may be needed anyway (ADR-004) |
| cobra for CLI | Moderate | Standard choice, unlikely to change |

## External Dependencies

| Dependency | Failure mode | Stability | Fallback |
|---|---|---|---|
| git CLI | Layer clone/push fails | Stable | None needed |
| podman + podman-compose | Container build/lifecycle fails | Stable | Docker adapter v2 |
| lnai | Sync command fails | Medium (239★) | Configurable `[sync].command` |
| mergo | Merge edge cases | Stable (9k★) | Custom transformer |
| hadolint | Containerfile lint unavailable | Stable | Non-blocking skip |

## Verification

Plan execution is complete when:

1. All 10 acceptance tests pass (`go test -tags acceptance ./test/acceptance/...`)
2. CI green: unit, lint, format on every push
3. Golden path works: `afb init → afb sync → afb build → afb up → afb doctor` → clean
4. `docs/developing.md` accurate and sufficient to onboard
5. `CHANGELOG.md` has entries per keepachangelog.com
6. Conventional commits throughout git history

## Resolved Questions

1. **License**: MIT
2. **CI podman**: podman is pre-installed on ubuntu-latest runners. podman-compose is NOT — install via `webgtx/setup-podman-compose@v1` action. E2e/integration jobs that need podman run in CI without issue.
3. **Conventional commit scopes**: Go package names — `feat(manifest):`, `fix(compose):`, `refactor(generate):`, etc.
4. **mergo version**: pin `dario.cat/mergo@v1.0.2` (latest stable)
5. **`afb build --generate-only`**: yes, add flag. Generate Containerfile + compose.yaml without invoking podman. Enables unit-level validation (hadolint, podman-compose config) without a running container runtime. Full `afb build` (no flag) generates + builds.
