---
feature: agent-adapter-demo
spec_version: 1.0
date: 2026-03-23
status: final
---

# Agent Adapter Demo — Design Draft

## Problem

The repository currently proves:
- Cangjie package → CLI generation
- Browser-based workflow with upload/download
- `help --json` for machine-readable command discovery

It does **not** prove that cliver is an agent/backend integration layer.
`runFromArgs()` exists as a library entrypoint, but no runnable non-browser
client demonstrates the full protocol flow from a programmatic caller.

The open question from `agent-integration/design.md` Feature C (deferred):

> "A minimal Node.js script (or Python) that connects to a Cliver WebSocket
> server, calls `help --json` to build a local command registry, exposes each
> command as a tool-call compatible function, handles upload/download."

This feature delivers that proof.

---

## Decision

**Minimal Node.js demo script**, placed under `cliver-tests/demo/agent-adapter.js`.

Rationale:
- Node.js reuses the existing `ws` dependency already in `sample_cangjie_package/`
- A standalone script (not part of build or test pipeline) matches the explicit
  decision in `agent-integration/design.md`: "standalone proof-of-concept"
- Python was considered but adds a new runtime dependency

**What it does:**
1. Connect to a running `cli_ws_server.js`
2. Send `{ line: "help --json" }` and parse the command registry
3. Upload a file via `{ type: "upload", ... }` protocol
4. Execute a file-processing command using the uploaded file handle
5. Download the output via `{ type: "download", path: "..." }` protocol
6. Log each step with the raw protocol messages and results

**What it does not do:**
- It is not a production agent framework integration
- It does not implement any agent planning or tool-call binding layer
- It does not handle errors beyond basic validation

**Not chosen:**
- In-process use of `runFromArgs()` directly: this would bypass the WebSocket
  backend and not prove the full protocol path. The protocol proof is more
  valuable since it covers the same path a real agent framework would use.

---

## Scope

**In scope:**
- `cliver-tests/demo/agent-adapter.js`: single standalone script
- Uses the existing `sample_cangjie_package` as the target Cangjie package
- Runs against an already-started `cli_ws_server.js`
- Proves: discover → upload → execute → download in one session
- Script is self-documented (inline comments explain each protocol step)

**Out of scope:**
- Integration into `scripts/build_and_test.sh`
- Part of any CI pipeline
- Persistent session state across multiple connections
- Multiple command sequences (one file workflow is sufficient for proof)
- Error recovery or retry logic

---

## Protocol

The adapter uses the existing `cli_ws_server.js` WebSocket protocol
(documented in `dev-journal/features/2026-03-17-upload-download/design.md`
and `dev-journal/features/2026-03-19-agent-integration/design.md`).

No protocol changes. This is a client-side proof only.

### Handle substitution mechanism (corrected from agent-integration design)

The upload handle is **not** registered as a CLI env var. Instead, the Node backend
stores handles in a per-connection JS WeakMap (`connHandles`). When the client sends
`{ line: "buildUploadReport $DEMO_INPUT" }`, the server calls `substituteHandles()`
to expand `$DEMO_INPUT` → raw file path **before** passing the line to the CLI process.

Consequence: the adapter must use a **single WebSocket connection** for the full session
so that handles registered during upload are visible when the execute command arrives.

### Session flow

```
adapter → server: { line: "help --json" }
server → adapter: { stdout: "<json>", stderr: "" }

adapter → server: { type: "upload", filename: "demo_input.txt", data: "<base64>" }
server stores: connHandles[ws]["DEMO_INPUT"] = "/tmp/cliver/uploads/..."
server → adapter: { type: "upload_result", path: "/tmp/cliver/...", handle: "DEMO_INPUT" }

adapter → server: { line: "buildUploadReport $DEMO_INPUT" }
server expands: "buildUploadReport /tmp/cliver/uploads/..." (before CLI call)
server → adapter: { stdout: "/tmp/cliver/outputs/demo_input.txt.report.txt", stderr: "" }

adapter → server: { type: "download", path: "/tmp/cliver/outputs/..." }
server → adapter: { type: "download_result", filename: "...", data: "<base64>" }

adapter → server: { line: "exit" }
```

---

## Testable Behaviors

> Note: This demo script is not part of the automated test suite.
> "Testable behaviors" here describes what a human reviewer verifies
> by running the script and reading its output.

### Step 1 — Discovery via help --json

**Expected:** Script prints a parsed list of commands from `help --json`.
Each command shows name, params, and packagePath.

**Pass criterion:** Command list is non-empty and contains at least the
`lineCount` command from the sample package.

---

### Step 2 — Upload

**Expected:** Script uploads a local text file, receives `upload_result`
with both `path` and `handle` fields.

**Pass criterion:** `handle` field is non-empty (e.g. `INPUT_TXT`).
Uploaded file is accessible at the returned `path`.

---

### Step 3 — Execute command with uploaded file

**Expected:** Script sends `{ line: "lineCount $INPUT_TXT" }` using the
handle from Step 2. Server runs the Cangjie `lineCount` function.

**Pass criterion:** `stdout` contains a numeric line count matching the
uploaded file's actual line count. `exitCode` is 0.

---

### Step 4 — Download output (if lineCount produces a file)

If the sample package's `lineCount` command produces a file artifact under
`/tmp/cliver/`, the adapter downloads it.

**Pass criterion:** If a file path appears in stdout, `download_result` is
received with non-empty `data`.

> Note: If `lineCount` returns inline text (not a file path), Step 4 is
> skipped and the proof chain is: discover → upload → execute with handle.

---

### Overall pass criterion

The script exits 0 and prints:
```
[1/4] Discovery: OK  (N commands found)
[2/4] Upload: OK     (handle: INPUT_TXT)
[3/4] Execute: OK    (stdout: "5")
[4/4] Session: closed
```

---

## Security Constraints

- Script connects only to localhost (hardcoded `ws://localhost:<port>`)
- No user-supplied inputs — file content and command are hardcoded in the demo

---

## Known Limitations

- This is a single-shot demo, not a reusable adapter library
- The `runFromArgs()` in-process path is NOT exercised; only the WebSocket path is proven
- The shared full-line execution gap (`;` / `NAME=cmd`) is still not addressed
  (separate future feature: `runline-semantics`)
- No test agent coverage (this feature has no independent protocol tests in
  `cliver-tests/`; human-run verification is the acceptance gate)
