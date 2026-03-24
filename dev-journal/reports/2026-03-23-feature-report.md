# Feature Report: Upload / Download & Agent Hook-Up

**Branch:** `feature/upload-download`
**HEAD:** `43f59aa`
**PR:** https://github.com/BinaRoy/cliver/pull/1
**Date:** 2026-03-23

---

## What Was Built

This feature adds three things on top of the existing CLI generator:

**1. File transfer protocol (WebSocket)**

The generated Node.js backend now handles two new message types:

```
{ type: "upload", filename: "demo.txt", data: "<base64>" }
→ { type: "upload_result", path: "/tmp/cliver/uploads/demo.txt", handle: "$DEMO" }

{ type: "download", path: "/tmp/cliver/outputs/demo.txt.report.txt" }
→ { type: "download_result", data: "<base64>" }
```

Uploaded files land in `/tmp/cliver/uploads/`. Package-generated output files in `/tmp/cliver/outputs/` are downloadable. The backend substitutes `$HANDLE` with the actual uploaded path before dispatching a command line, so callers don't have to track full paths manually.

**2. A real file-processing command in the sample package**

`buildUploadReport(inputPath: String): String` in `sample_cangjie_package/src/main.cj`:

- reads the file at `inputPath`
- computes line count, char count, first-line uppercase preview
- writes a `.report.txt` to `/tmp/cliver/outputs/`
- returns the output path as a string

This makes the sample package an actual file workflow participant, not just a toy class demo.

**3. Agent-hardened generated driver**

After the `agent-backend-hardening` work (same branch), the generated `cli_driver.cj` also has:

- `help --json` now includes `commandKind` (`"constructor"` / `"function"` / `"method"`) and param `role` (`"path"` / `"ref"` / `"plain"`) on every command and parameter. Example from the currently generated driver:

  ```json
  {"name":"buildUploadReport","commandKind":"function","packagePath":"/","returnType":"String",
   "params":[{"name":"inputPath","type":"String","role":"path"}]}
  ```

  ```json
  {"name":"Student","commandKind":"constructor","packagePath":"/","returnType":"Student",
   "params":[{"name":"name","type":"String","role":"plain"},{"name":"id","type":"Int64","role":"plain"}]}
  ```

- Instance methods (e.g. `Student getName`, `Student setName`) are now in the schema with `className` and `commandKind: "method"`.

- `session finished` text is written to stderr only. Command output in stdout is clean.

- `_runLine()` is a shared execution layer called by both `_serveStdin()` and `main()`. `;`-separated commands, `NAME=cmd` assignment, and `$NAME` substitution work identically on the CLI and WebSocket paths.

---

## Test Results

| Suite | Count | Result |
|-------|-------|--------|
| Cliver core (`cjpm test`) | 16 | ✓ all pass |
| Sample package (`cjpm test`) | 16 | ✓ all pass |
| Backend protocol (`node test_backend.js`) | upload→exec→download chain | ✓ pass |
| Adapter demo (`scripts/run_adapter_demo.sh`) | exit 0 | ✓ automated |

Sample package now has 16 tests including:
- `buildUploadReportCreatesDownloadableFileUnderTmpCliver`: writes a real file to `/tmp/cliver/outputs/`, asserts content
- `sessionStoreAndInstanceMethodsWorkAcrossMultipleCalls`: proves `runFromArgs()` with shared `store` persists objects across calls (create → getName → setName → getName)
- `helpJsonIncludesCommandListAndFileProcessorSchema`: asserts `commandKind`, `role`, `className` fields in JSON output

---

## The Demo

The complete workflow can be run in two ways:

**Automated (script):**
```bash
./scripts/run_adapter_demo.sh
```
This starts the WebSocket server, runs `cliver-tests/demo/agent-adapter.js` (a Node.js client that calls discover → upload → execute → download automatically), and exits 0 on success.

**Manual (browser):**
```bash
# From repo root
cjpm build
PKG_SRC=sample_cangjie_package ./target/release/bin/main
cd sample_cangjie_package && cjpm build
node web/cli_ws_server.js
# Open http://localhost:8765
```
Steps: call `help --json` → upload a file → run `buildUploadReport $HANDLE` → click download on the output path.

What to show in either case:
1. `help --json` returns a machine-readable schema with `commandKind` and `role`. An agent reads this to know what the package can do and what each parameter means.
2. Upload a text file → backend assigns it a path under `/tmp/cliver/uploads/` and a `$HANDLE`.
3. Run `buildUploadReport $HANDLE` → the Cangjie package reads the file and writes a report to `/tmp/cliver/outputs/`.
4. Download the output path → agent or browser retrieves the result artifact.

This proves: **upload/download is not a UI decoration. It's a real data handoff between external caller and Cangjie package code.**

---

## Why It Can Hook Up With Agents Like OpenClaw

An agent needs four things to use a backend tool:

| Requirement | How Cliver provides it |
|-------------|------------------------|
| Discover what commands exist and what their parameters mean | `help --json` with `commandKind` + param `role` |
| Send files in as inputs | Upload protocol → server-side path + handle |
| Invoke package capabilities | WebSocket `{ line: "cmd arg1 arg2" }` or `runFromArgs()` in-process |
| Retrieve generated output files | Download protocol by path |

`cliver-tests/demo/agent-adapter.js` is a working Node.js implementation of exactly this: it calls `help --json`, uploads a file, runs `buildUploadReport` with the handle, reads the output path from stdout, and downloads the result. It passes without any manual interaction.

The key distinction from a browser demo: the adapter script has no UI. It's a program calling another program. That's the same topology as an agent calling a backend tool.

Development workflow and test layers: [2026-03-23-dev-workflow.md](./2026-03-23-dev-workflow.md)
