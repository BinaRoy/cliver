---
feature: agent-integration
spec_version: 1.0
date: 2026-03-19
status: final
---

# Agent Integration — Design Draft

## Background

The upload/download feature (2026-03-17) delivered file transfer over WebSocket.
Post-delivery review identified three gaps against the stated requirement and the
downstream OpenClaw integration goal:

1. **Env var handle** — requirement said "env vars as a handle"; implementation
   returns raw paths. The CLI driver already supports `$VAR` substitution internally
   (per `_tokenizeStdinLine` in `codegen.cj`), but the upload result does not
   automatically register a handle into the session.

2. **Machine-readable schema** — `help` output is human-readable prose. An agent
   framework (OpenClaw or similar) must text-parse it to discover command
   signatures. A structured `help --json` response would unblock automated tool-call
   binding.

3. **Agent adapter** — no reference integration exists to prove the end-to-end path
   from an agent framework to a Cangjie function via Cliver.

---

## Proposed Features (this phase)

### Feature A — Server-side env var handle on upload

**Requirement closure:** "env vars as a handle"

**Design:**

After a successful upload, the server sends a `{ line: "HANDLE = echo <path>" }`
command to the CLI session stdin **before** returning `upload_result`. This
registers the path as a session env var accessible via `$HANDLE` in all subsequent
commands.

Handle naming: `UPLOAD_<N>` (monotonic counter per WebSocket session, starting at 1).

Extended `upload_result`:
```js
{ type: "upload_result", path: "/tmp/cliver/uploads/...", handle: "UPLOAD_1" }
```

The UI sidebar shows both the path and the handle. The "Insert path" button inserts
`$UPLOAD_1` instead of the raw path.

**Scope:** Change confined to `_backendScriptTemplate()` in `src/main.cj` and
`index.html` template. No Cangjie changes.

**Decision (confirmed):** Filename-derived handle: basename without extension,
uppercased, non-alphanumeric chars replaced with `_`.
Examples: `data.csv` → `DATA_CSV`, `my-report.txt` → `MY_REPORT_TXT`.
Collision (same handle already registered in session): append monotonic suffix
`_2`, `_3`, etc.

Extended `upload_result`:
```js
{ type: "upload_result", path: "/tmp/cliver/uploads/...", handle: "DATA_CSV" }
```

---

### Feature B — `help --json` structured output

**Requirement:** Agent schema discovery without text parsing.

**Design:**

Add `--json` flag recognition to the generated `cli_driver.cj` help branch.
Output: a JSON object on stdout listing all commands.

```json
{
  "commands": [
    {
      "name": "lineCount",
      "params": [{"name": "path", "type": "String"}],
      "returnType": "String",
      "packagePath": ""
    },
    ...
  ]
}
```

**Scope:** Change in `codegen.cj` (generated driver's help dispatch). No protocol
change — this is just a `{ line: "help --json" }` command that returns JSON on stdout.

**Decision (confirmed):** `help --json` as a flag on the existing `help` command.
`sessionClosed` is NOT sent after `help --json` — the session stays open,
matching the behavior expected by agent callers (they send `help --json` as a
discovery step within an active session).

---

### Feature C — OpenClaw reference adapter (demo)

**Goal:** Prove feasibility; not a production integration.

A minimal Node.js script (or Python) that:
1. Connects to a Cliver WebSocket server
2. Calls `help --json` to build a local command registry
3. Exposes each command as a tool-call compatible function
4. Handles upload/download via the protocol

**Scope:** New file in a `demo/` or `adapters/` directory; not part of Cliver's
build or test pipeline. Standalone proof-of-concept.

**Decision (confirmed):** Separate PR. Not in scope for this phase.

---

## Dependency Order

```
Feature A (env var handle)
    └─ standalone, no dependencies

Feature B (help --json)
    └─ standalone; codegen change
    └─ Feature C depends on B (needs machine-readable schema)

Feature C (adapter)
    └─ depends on A + B for clean UX
    └─ can be done with current protocol as a workaround (text-parse help)
```

Recommended order: **A → B → C**

---

## Affected Files

| File | Feature | Change type |
|------|---------|-------------|
| `src/main.cj` (`_backendScriptTemplate`) | A | Add handle counter; inject env var command; extend upload_result |
| `sample_cangjie_package/web/index.html` | A | Show handle in sidebar; "Insert path" uses `$HANDLE` |
| `src/codegen.cj` | B | Add `--json` branch in help dispatch |
| `src/codegen_test.cj` or `src/codegen.cj_test` | B | Unit test for JSON output format |
| `cliver-tests/` | A + B | New independent protocol tests |
| `demo/openclaw-adapter.js` (new) | C | Reference adapter script |

---

## Out of Scope (this phase)

- Per-connection temp file cleanup (already deferred from Phase 1)
- File size limits / MIME validation
- Streaming upload (large files)
- Persistent env vars across sessions
- Full OpenClaw production integration

---

## Decisions (confirmed 2026-03-19)

| 决策点 | 结论 |
|--------|------|
| Handle 命名 | 文件名派生（`DATA_CSV`），冲突时加 `_2`/`_3` 后缀 |
| `help --json` 入口 | flag on `help`，session 不关闭 |
| Feature C 范围 | 单独 PR，本阶段不做 |
| PR 策略 | A+B 并入当前 `feature/upload-download` PR |
| 测试策略 | 复用 `cliver-tests/` repo，新增测试文件 |
