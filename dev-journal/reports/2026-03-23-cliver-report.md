## What Cliver Should Be

> Cliver generates a CLI driver, WebSocket backend, and in-process session API from a Cangjie package's public API — no manual wiring required.

"Agent-ready" means the generated interface has enough structure — typed params, `commandKind`, param `role`, file handoff — that a program can use it without a human in the loop.

## What Cliver Does

Cliver reads a Cangjie package and generates two things:

**1. A CLI driver** (`cli_driver.cj`) — a Cangjie source file compiled into the same package. It maps every public function, constructor, and instance method to a command name, handles argument parsing and type conversion, maintains an in-memory object store so constructed objects can be referenced across commands (`ref:1`, `ref:2`, …), and exposes `runFromArgs(args, store, nextId)` for in-process callers.

**2. A WebSocket backend** (`cli_ws_server.js`) + browser UI (`index.html`) — a Node.js server wrapping the compiled CLI binary. It handles `{ line: "..." }` command messages, file upload/download, and `$HANDLE` substitution.

The net result: a Cangjie package that had no external interface now has a CLI, a WebSocket API, a browser UI, and an in-process library API — all generated from source, no manual wiring.

---

## Scope

- Command discovery (`help --json` with structured schema) so agents can find what the package does
- Argument dispatch and type conversion
- In-memory session state (object store + ref handles)
- File handoff: route uploaded files to package commands, route output files back out
- Machine-readable output (stdout/stderr separated, command output clean)

---

## What It Can Do Today

As of commit `43f59aa`, against each scope item:

**Command discovery (`help --json`):** ✓
Returns a full schema with `commandKind` (`"constructor"`, `"function"`, `"method"`) and param `role` (`"path"`, `"ref"`, `"plain"`) on every entry, plus `className` for methods. An agent reading this knows which commands create objects, which take file paths, and which operate on existing refs.

**Argument dispatch and type conversion:** ✓
The generated driver converts string arguments to target types (`String`→`Int64`/`Float64`/`Bool`) at runtime, resolves `ref:N` to objects in the store, and matches overloads in manifest order. Type mismatches and missing refs produce a non-zero exit code with a stderr message.

**In-memory session state (object store + ref handles):** ✓
`runFromArgs(args, store, nextId)` lets a caller hold a session across calls. Objects constructed in one call persist in `store` for the next. `nextId` threads through to keep ref IDs monotonically increasing.

```
runFromArgs(["Student", "new", "Alice", "1001"], store, 1)    → ref:1, nextId=2
runFromArgs(["Student", "getName", "ref:1"], store, 2)        → stdout: "Alice"
runFromArgs(["Student", "setName", "ref:1", "Bob"], store, 3) → exitCode 0
runFromArgs(["Student", "getName", "ref:1"], store, 4)        → stdout: "Bob"
```

**File handoff:** ✓
Upload → `/tmp/cliver/uploads/`, backend substitutes `$HANDLE` with the actual path before dispatching; package writes output to `/tmp/cliver/outputs/`, download retrieves by path. CLI and WebSocket share `_runLine()` so both paths have identical line-level semantics. Proven end-to-end by `test_backend.js` and `scripts/run_adapter_demo.sh`.

**Machine-readable output:** ✓
Command stdout and stderr are separated via the `<<<CLIVE_STDERR>>>` delimiter. Session meta text (`session finished`) goes to stderr only. Stdout contains command results only.

---

## Gaps Between Current Implementation and a Good Cliver

**No `returnRole` in schema**

The schema has `returnType` (e.g. `"String"`), but nothing to tell an agent whether that String is a downloadable artifact path or a plain text message. `buildUploadReport` returns a file path, but the schema can't distinguish that from a String that's a count or a status.

The fix follows the same pattern as `role` inference: for `returnType == "String"` where the function name contains report / path / output, emit `returnRole: "artifact"` in the schema.

**`runFromArgs` doesn't support full line semantics**

`runFromArgs(args, store, nextId)` wraps the argument array as a single segment and calls `_runSegments` directly — it doesn't go through `_runLine`. In-process callers can't use `;` to chain commands, `NAME=cmd` assignment, or `$NAME` substitution. Those only work on the WebSocket path.

Nothing is blocked by this today, but the two entry points have unequal capabilities. The fix is a new `public func runLine(line: String, store, nextId): RunFromArgsResult` in codegen — about 10–20 lines. This belongs in a future feature alongside `returnRole`, not in the upload/download PR.

**Parser silently drops functions it can't handle**

Generic functions and complex multi-line signatures are skipped with no indication in the schema. An agent may be missing commands without knowing it. No impact on the current sample package; a real risk for any non-trivial Cangjie package.

**No function descriptions**

The parser doesn't extract comments or docstrings. Agents see the signature but not what the function actually does. The current `commandKind`, `role`, and parameter names already give enough structure for planning — worth addressing once Cliver is used with real business packages.
