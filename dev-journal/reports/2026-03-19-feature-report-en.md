# Feature Delivery Report: File Upload/Download + Environment Variable Handles

**Date:** 2026-03-19
**Branch:** `feature/upload-download`
**PR:** https://github.com/BinaRoy/cliver/pull/1
**Status:** Open, pending merge

---

## 1. Feature Development Results

### Requirement

> Add send/receive files using environment vars as a handle.

### Is the requirement met?

**Yes, fully met.** Details below.

#### Commits in this PR (7 total, since `1b1aeb8`)

| Commit | Description |
|--------|-------------|
| `d9c3cff` | Parser/codegen fix: skip generic functions, fix cross-subpackage import paths |
| `5998e95` | **Core**: WebSocket protocol extension — new `upload` / `download` message types; generated `cli_ws_server.js` includes `handleUpload` / `handleDownload` |
| `11e7a8b` | `index.html` template: add file upload/download UI (left sidebar, drag-drop zone, download buttons) |
| `5f1af96` | Project infrastructure (dev-journal, test framework, test fixtures) |
| `bcbae73` | Clean up `.gitignore`, remove dev-process files |
| `df20c22` | Fix UI regressions (restore original CSS/JS behaviour; new additions only, nothing removed) |
| `fe56c22` | **Env var handle**: `upload_result` gains `handle` field; `help --json` structured output |

#### Key Design

**Upload flow (environment variable handle):**

```
Agent/User uploads a file
    → { type: "upload", filename: "data.csv", data: "<base64>" }
    ← { type: "upload_result", path: "/tmp/cliver/uploads/...", handle: "DATA_CSV" }

Agent/User uses the handle in a command
    → { line: "lineCount $DATA_CSV" }
      (server substitutes $DATA_CSV → actual path before spawning the CLI process)
    ← { stdout: "3 lines" }
```

**Handle naming rules:**
- Basename without extension → uppercase → non-alphanumeric chars replaced with `_`
- Examples: `my-data.csv` → `MY_DATA`, `report (v2).pdf` → `REPORT__V2_`
- Collision within the same session: auto-suffix `_2`, `_3`, etc.

**Download flow:**

```
Agent/User requests a file
    → { type: "download", path: "/tmp/cliver/uploads/..." }
    ← { type: "download_result", filename: "out.txt", data: "<base64>" }
```

**`help --json` (new — for agent command schema discovery):**

```
→ { line: "help --json" }
← { stdout: '{"commands":[{"name":"lineCount","packagePath":"/","returnType":"String","params":[{"name":"path","type":"String"}],...}],"builtins":["echo","dir","help","cd"]}' }
```

#### Security

- **Upload**: filename sanitised via `path.basename()` + regex; UUID prefix prevents collisions
- **Download**: path canonicalised with `path.resolve()` then checked against `/tmp/cliver/`; path traversal attacks are blocked
- **Handle substitution**: done entirely at the server layer — the CLI process only ever sees the resolved path

---

## 2. Verification Approach and Results

### 2.1 Human verification (Web UI)

**Start the server:**

```bash
cd file-demo   # or any Cliver-generated package
node web/cli_ws_server.js
# Open http://localhost:8765 in a browser
```

**Steps and expected outcomes:**

| Action | Expected result |
|--------|----------------|
| Drag a local file onto the left-hand Files panel | File entry appears in the list showing `$FILENAME` (not the raw path) |
| Click "Insert" | `$FILENAME` is inserted at the cursor position in the command input |
| Type `lineCount $FILENAME`, press Shift+Enter | Returns the line count (server substituted the handle transparently) |
| Type `help --json`, press Shift+Enter | Returns a JSON command list |
| Type `toUpperCase $FILENAME /tmp/cliver/uploads/out.txt` | Returns the output path; a `⬇ out.txt` button appears inline in the response |
| Click `⬇ out.txt` | Browser downloads the file; content is uppercased |
| Upload a second file with the same name | List shows `$FILENAME_2`; the two handles are independent |

### 2.2 Agent verification (tool / OpenClaw-style framework)

**Method:** `manual_check.js` — a single persistent WebSocket connection that simulates a complete agent session.

```bash
node web/cli_ws_server.js &
PORT=9877 node web/manual_check.js
```

**7 scenarios covered:**

| # | Scenario | Result |
|---|----------|--------|
| 1 | `help` returns a human-readable command list | ✓ |
| 2 | `help --json` returns valid JSON schema with params and returnType | ✓ |
| 3 | Upload → `upload_result` contains both `path` and `handle` (`$SAMPLE`) | ✓ |
| 4 | Within the same session, `$SAMPLE` in a command is correctly substituted and executed | ✓ |
| 5 | Uploading the same filename again in the same session yields `$SAMPLE_2` | ✓ |
| 6 | Download → base64 round-trip content matches the original exactly | ✓ |
| 7 | Downloading `/etc/passwd` → `Access denied` (path traversal blocked) | ✓ |

**Result: 7/7 passed.**

Integration tests (`test_backend.js`) and unit tests (`cjpm test`) also pass in full.

---

## 3. Hooking up to OpenClaw: current status and roadmap

### 3.1 What is already in place

| Capability | Status | Notes |
|------------|--------|-------|
| WebSocket communication protocol | ✅ | Plain JSON; any language can implement a client |
| File upload to server | ✅ | Base64-encoded; any file type supported |
| Environment variable handle | ✅ | `$HANDLE` substituted transparently at the server layer |
| File download | ✅ | Base64 response; can be written to disk or processed in-memory |
| Command schema discovery | ✅ | `help --json` returns a structured command list |
| Security constraints | ✅ | Path traversal protection, filename sanitisation |

All the underlying capabilities an OpenClaw adapter needs **are already in place**.

### 3.2 What still needs to be built

In dependency order:

#### Phase 1 (planned, separate PR): OpenClaw reference adapter

Goal: a standalone script that proves the full chain — from agent framework to Cangjie function — is viable.

```
OpenClaw tool-call
    → adapter: parse tool schema, map to Cliver command
    → WebSocket: send { line: "..." } or upload/download message
    → Cliver WS server → CLI binary → Cangjie function
    ← result returned and adapted to tool-call response format
```

Components to build:
- **Schema mapping**: `help --json` output → OpenClaw tool definition format (`name`, `description`, `parameters` as JSON Schema)
- **Session management**: one WebSocket session per agent task, so handles remain valid across calls
- **File lifecycle**: upload at task start; optional cleanup at task end
- **Error mapping**: `download_error` / `upload_error` → tool-call error response

#### Phase 2 (future): Production-grade integration

- WebSocket session pool (concurrent agents)
- Automatic file cleanup on session close (`/tmp/cliver/uploads/<session-id>/`)
- Streaming upload for large files
- `help --json` extension: add `description` field per command (for LLM semantic understanding)

### 3.3 Feasibility analysis

**High feasibility.** Key arguments:

1. **Simple protocol**: plain JSON over WebSocket, no special dependencies. Any agent framework with WebSocket support can integrate without an SDK.

2. **Schema is already machine-readable**: `help --json` already provides `name / params / returnType`. The gap between this and an OpenClaw tool definition is purely field mapping (~30–50 lines of adapter code).

3. **File transfer is end-to-end validated**: the upload → handle → command → download chain has been verified by `manual_check.js`, which mirrors the exact call pattern an agent would use.

4. **Remaining risks**:
   - OpenClaw's specific tool-call API format needs to be matched against their documentation (unknown variable)
   - No `description` field yet → the agent LLM cannot infer command semantics (can be addressed later by extracting Cangjie doc comments)
   - Concurrent multi-session behaviour is untested (Node.js single-process architecture supports it in theory; needs load testing)

**Conclusion:** A working OpenClaw demo adapter is estimated at 1–2 days of work, primarily schema mapping and session management. Production-grade integration requires additional work on concurrency and file cleanup, but there are no architectural blockers.
