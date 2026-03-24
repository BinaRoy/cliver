# Cliver Upload/Download And Agent Hook-Up Gap Analysis

## Purpose

This document captures what still needs to be completed for the `feature/upload-download` line of work, with a focus on the question:

**Does cliver already sufficiently prove that agents can hook up to Cangjie packages through cliver and benefit from upload/download in a real workflow?**

Short answer:

- **For a manager demo:** almost yes, especially with the local demo-package additions
- **For a stronger technical claim about agent integration:** not fully yet

The key distinction is:

- proving a **web demo**
- versus proving a real **agent-ready integration layer**

---

## Current Status

What already exists in the repository:

- `help --json` command discovery
- generated CLI driver for Cangjie packages
- `runFromArgs()` as an in-process library entrypoint
- generated Node WebSocket backend
- upload/download support in that backend
- sample package and sample backend tests

What is still incomplete:

- a minimal real **agent/backend hook-up proof**
- a shared execution layer for full line semantics
- richer discovery schema for agents
- promotion of the local file-workflow demo into the tracked feature branch

---

## Evidence Summary

The current design intent is already visible in the repo and analysis:

- [docs/analysis/cliver-code-reading-zh.md](/home/gloria/tianyue/cliver/docs/analysis/cliver-code-reading-zh.md) lines 1324-1351 explicitly recommend:
  - first completing the demo proof chain
  - then completing the agent backend proof
- [docs/analysis/cliver-code-reading-zh.md](/home/gloria/tianyue/cliver/docs/analysis/cliver-code-reading-zh.md) lines 1238-1239 state that the biggest remaining evidence gap is not the page, but whether an agent backend can truly hook up
- [docs/browser-terminal-actors.md](/home/gloria/tianyue/cliver/docs/browser-terminal-actors.md) describes the Node backend as current reality and a Cangjie actor backend as an optional future direction
- [docs/limitations-and-future.md](/home/gloria/tianyue/cliver/docs/limitations-and-future.md) documents that `runFromArgs()` does not yet cover full line semantics

Also, local/remote branch inspection shows:

- local `feature/upload-download` and `origin/feature/upload-download` are identical
- both resolve to commit `fe56c22afc20f90d281ad7b3593c5e1346cd2ad7`
- so there is **no confirmed remote update that must be pulled first**

---

## Must-Have Gaps

## 1. Minimal Agent Backend Hook-Up Demo (→ feature entry: agent-adapter-demo)

Why this needs to be completed:

- Right now the repository proves a browser workflow and a generated backend.
- It does **not** yet strongly prove that cliver is an agent/backend integration layer that another long-lived backend can directly use.
- This is the most important missing technical proof.

Current implementation:

- `runFromArgs()` exists and clearly points toward in-process backend use.
- The actual runnable backend in the repo is still the generated Node backend.
- There is no real actor demo backend or equivalent session-holding backend in the repository.

Evidence:

- [docs/analysis/cliver-code-reading-zh.md](/home/gloria/tianyue/cliver/docs/analysis/cliver-code-reading-zh.md) lines 1342-1351 define Phase 2 as “补 agent backend 证据”
- [docs/analysis/cliver-code-reading-zh.md](/home/gloria/tianyue/cliver/docs/analysis/cliver-code-reading-zh.md) lines 1238-1239 say the biggest evidence gap is whether the agent backend can really connect
- [docs/browser-terminal-actors.md](/home/gloria/tianyue/cliver/docs/browser-terminal-actors.md) presents the actor backend only as an optional approach, not as a shipped proof

Recommended completion:

- add a minimal backend demo that holds `store + nextId`
- use `runFromArgs()` directly across multiple requests in one session
- prove that cliver is not only a web CLI generator, but a backend-consumable tool interface layer

---

## 2. Promote The Local File Workflow Demo Into The Feature Branch

Why this needs to be completed:

- The strongest manager-demo proof now depends on local uncommitted changes.
- If those changes are not folded into `feature/upload-download`, the branch itself still does not fully show the intended proof chain.

Current implementation:

- the local worktree contains a minimal file-processing command in the sample package
- local tests now cover upload -> package command -> generated file -> download
- local runbook exists
- these changes are not yet reflected in the remote feature branch

Evidence:

- local modified files include:
  - [sample_cangjie_package/src/main.cj](/home/gloria/tianyue/cliver/sample_cangjie_package/src/main.cj)
  - [sample_cangjie_package/src/cli_driver_test.cj](/home/gloria/tianyue/cliver/sample_cangjie_package/src/cli_driver_test.cj)
  - [sample_cangjie_package/test_backend.js](/home/gloria/tianyue/cliver/sample_cangjie_package/test_backend.js)
  - [docs/demo-runbook.md](/home/gloria/tianyue/cliver/docs/demo-runbook.md)
- local and remote `feature/upload-download` currently match, so these additions are not yet upstreamed

Recommended completion:

- fold the local sample package demo, verification, and runbook into `feature/upload-download`
- make the branch itself self-sufficient as demo evidence

---

## Should-Have Gaps

## 3. Enrich `help --json` For Agent Use

> **Status correction:** `help --json` is already implemented as of commit `fe56c22`
> (`agent-integration` Feature B). This gap is about **enriching** the existing schema,
> not completing a missing feature.

Why this enrichment matters:

- The current schema is functional for basic discovery, but thin for real agent planning and tool selection.
- Agents benefit from knowing not just argument types, but argument roles and artifact behavior.

Current implementation (`help --json` already exposes):

- command name, package path, return type
- parameter names and types
- builtins

What is still missing from the schema:

- parameter role metadata (`path`, `ref`, or `plain`)
- whether a command may produce a file artifact under `/tmp/cliver/`
- explicit distinction between builtins, constructors, package functions, and methods

Evidence:

- [src/codegen.cj](/home/gloria/tianyue/cliver/src/codegen.cj) contains `_printHelpJson()`
- [docs/analysis/cliver-code-reading-zh.md](/home/gloria/tianyue/cliver/docs/analysis/cliver-code-reading-zh.md) line 1193 says the schema is still thin
- [docs/analysis/cliver-code-reading-zh.md](/home/gloria/tianyue/cliver/docs/analysis/cliver-code-reading-zh.md) line 1253 points out that path-oriented capabilities are not marked

Recommended completion:

- add parameter role metadata such as `path`, `ref`, or `plain`
- indicate whether a command may produce a file path under `/tmp/cliver/`
- distinguish builtins, constructors, package functions, and methods more explicitly

## 4. Shared Full-Line Execution Layer

> **Downgraded from Must-Have.** The Node backend already handles full-line
> semantics (`;`, `NAME = cmd`, `$NAME`) via `main()`. This is an architectural
> cleanup, not a prerequisite for the agent adapter demo.

Why this is worth completing eventually:

- `runFromArgs(args, store, nextId)` handles single-command argv only
- callers needing full-line semantics must pre-split or use the WebSocket path
- a shared `runLine()` would make in-process use of cliver cleaner

Current implementation:

- `runFromArgs(args, store, nextId)` exists in generated driver
- `main()` still carries the richer whole-line behavior
- Node backend's `substituteHandles()` handles `$NAME` server-side (not CLI-side)

Recommended completion (when prioritized):

- add a reusable `runLine(...)` or `parseLine + runSegments(...)` layer in generated driver
- have CLI and any future in-process backend share that layer

---

## 5. Make File Workflow Verification A First-Class Regression Gate

Why this needs to be completed:

- Upload/download existing is not enough.
- The actual value proposition is that uploaded files become package inputs and package outputs become downloadable artifacts.
- That full chain should be locked down as a required regression check.

Current implementation:

- sample backend tests exist
- local demo changes add a package-level file workflow test
- the main testing docs do not yet highlight this as a dedicated acceptance gate

Evidence:

- [sample_cangjie_package/test_backend.js](/home/gloria/tianyue/cliver/sample_cangjie_package/test_backend.js) already tests backend behavior
- [docs/TESTING.md](/home/gloria/tianyue/cliver/docs/TESTING.md) describes backend and integration layers, but not yet this exact workflow as a named acceptance criterion

Recommended completion:

- update [docs/TESTING.md](/home/gloria/tianyue/cliver/docs/TESTING.md)
- explicitly require one end-to-end proof:
  - upload file
  - pass uploaded path into generated package command
  - generate file under `/tmp/cliver/`
  - download generated file

---

## 6. Add A UI-Free Repeatable Demo Script

Why this needs to be completed:

- A browser demo is useful for managers.
- A no-UI repeatable script is stronger evidence for engineers and reviewers.
- It also makes regressions easier to spot.

Current implementation:

- there is now a runbook for human-followed demo steps
- there is not yet a dedicated “agent harness” style script that demonstrates the whole protocol flow without manual clicking

Evidence:

- [docs/demo-runbook.md](/home/gloria/tianyue/cliver/docs/demo-runbook.md) is human-oriented
- current repository proof still leans heavily on browser interaction for the visible workflow

Recommended completion:

- add a script that performs:
  - generation
  - discovery via `help --json`
  - upload protocol request
  - command invocation
  - download protocol request

---

## Nice-To-Have Gaps

## 7. Clean Up Execution Output Protocol

Why this is worth completing:

- Current output is good enough to work, but not ideal for machine consumers.
- Extra wrapper text makes downstream parsing more fragile than necessary.

Current implementation:

- the system works end-to-end
- some outputs still include wrapper/session text around the useful value

Evidence:

- practical verification required trimming or extracting the actual artifact path from command output
- [docs/browser-terminal-actors.md](/home/gloria/tianyue/cliver/docs/browser-terminal-actors.md) already frames the current Node backend as minimal infrastructure

Recommended completion:

- structure responses more cleanly
- make artifact outputs easier to detect without string scraping

---

## 8. Add A Second, More Task-Like Demo Command

Why this is worth completing:

- The current minimal file demo is good for proving integration.
- A second example would help product and engineering discuss what kinds of functions cliver should expose in practice.

Current implementation:

- the current local demo is intentionally minimal
- that is good for proof, but not yet a broader statement of intended product capability

Evidence:

- the quoted discussion explicitly says a small demo helps reveal what extra functions may be needed
- that suggests the demo should eventually inform function design, not just validate plumbing

Recommended completion:

- after the hook-up proof is solid, consider a second demo like:
  - summarize a file
  - transform a file
  - compare two files
  - extract structured content

---

## Recommended Order

If only the minimum practical set is completed, the best order is:

1. promote the current local demo and verification changes into `feature/upload-download`
2. add the minimal agent/backend hook-up demo
3. extract shared whole-line execution semantics
4. enrich `help --json`

This order matches the intent in the analysis discussion:

- keep the demo small
- use it to discover what cliver still lacks
- treat cliver as the conversion layer from Cangjie package capability to agent-usable tool interface

---

## Execution Status (updated 2026-03-23)

| Gap | Priority | Feature Entry | Status |
|-----|----------|---------------|--------|
| Gap 1 — minimal agent backend hook-up demo | Must-have | [agent-adapter-demo](features/2026-03-23-agent-adapter-demo/) | **✓ Complete** — `cliver-tests/demo/agent-adapter.js` verified exit 0; `scripts/run_adapter_demo.sh` added |
| Gap 2 — promote local demo | Must-have | _(direct commit)_ | **✓ Complete** — `sample_cangjie_package/src/main.cj` + `test_backend.js` + `cli_driver_test.cj` committed and verified |
| Gap 3 — enrich help --json | Should-have | [agent-backend-hardening](features/2026-03-23-agent-backend-hardening/) | **✓ Complete** — `commandKind`, param `role`, `className`, class methods added; tests assert all fields |
| Gap 4 — shared full-line execution layer | Should-have | [agent-backend-hardening](features/2026-03-23-agent-backend-hardening/) | **✓ Complete** — `_runLine()` extracted; `_serveStdin()` and `main()` share execution semantics |
| Gap 5 — file workflow regression gate | Should-have | _(direct commit)_ | **✓ Complete** — `buildUploadReportCreatesDownloadableFileUnderTmpCliver` test in `cli_driver_test.cj` |
| Gap 6 — repeatable demo script | Should-have | [agent-backend-hardening](features/2026-03-23-agent-backend-hardening/) | **✓ Complete** — `scripts/run_adapter_demo.sh` |
| Gap 7 — clean up output protocol | Nice-to-have | [agent-backend-hardening](features/2026-03-23-agent-backend-hardening/) | **✓ Complete** — `session finished` moved to stderr |
| Gap 8 — second demo command | Nice-to-have | — | Deferred — no current blocker |

**Implementation note on handle substitution:** The actual backend implementation
stores upload handles in a server-side JS WeakMap (`connHandles`) and substitutes
`$HANDLE` before passing the line to the CLI process. This differs from the
`agent-integration/design.md` description (which described CLI env var injection).
The server-side mechanism is what the demo script targets.

---

## Bottom Line

As of 2026-03-23, cliver demonstrates:

- package-to-CLI generation
- machine-readable command discovery with `commandKind` and param `role` fields
- in-process session proof via `runFromArgs()` with persistent object store across calls
- upload/download support in the generated backend
- complete `discover → upload → execute → download` protocol chain (automated via `scripts/run_adapter_demo.sh`)
- shared execution layer (`_runLine()`) ensuring CLI and backend use identical semantics

**The repository now proves that cliver is a backend-facing agent integration layer, not just a browser-facing CLI demo tool.**

The one remaining deferred item (Gap 8 — second demo command) is a nice-to-have for product scope discussions and has no impact on the agent integration proof.
