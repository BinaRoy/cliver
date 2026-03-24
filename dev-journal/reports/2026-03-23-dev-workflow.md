# Cliver Development Workflow

**Project:** Cliver (Cangjie package → CLI/backend generator)
**Date:** 2026-03-23

---

## Why Cliver's workflow is different from a normal application

Cliver is a code generator. Its output (`cli_driver.cj`) has to be compiled together with the target package before it can run. "Tests pass" means two things: the generator itself is correct, and the code it generates behaves correctly inside the target package. Both layers need coverage.

---

## Development process

**1. Write the design first — define what needs to be proven.**

Before writing code, define the question this feature has to answer. For the upload/download feature: "Can a non-human caller complete upload → execute → download without any manual help?" Every other decision follows from that. Without a concrete question, it's easy to ship an implementation that runs but proves nothing.

**2. Build the minimum that closes the proof.**

Don't aim for complete functionality — only build what's needed to answer the design question. `buildUploadReport` is 40 intentionally boring lines. Its only purpose is to give the upload→execute→download chain something real to process. Smaller implementations make cleaner evidence.

**3. Use the sample package as the integration test fixture.**

Tests in `sample_cangjie_package/src/cli_driver_test.cj` cover both the generator and the generated code simultaneously. Adding a test here means both sides have to be correct for it to pass. This is the only test location that constrains both sides at once.

**4. Verify the protocol layer in a separate file.**

`test_backend.js` only tests WebSocket server behavior — upload/download mechanics, handle substitution, output path routing. That's a completely different concern from the generated Cangjie driver's dispatch logic. Mixing them makes failures harder to locate.

**5. Automate the demo.**

`scripts/run_adapter_demo.sh` + `cliver-tests/demo/agent-adapter.js` turns the manual demo steps into a repeatable regression check. The demo runbook becomes a fallback for live explanation, not the only form of verification.

---

## Test layers

```bash
cjpm test                                   # Cliver core: parser, codegen, dir logic
cd sample_cangjie_package && cjpm test      # Generated driver + sample package logic
node test_backend.js                        # WebSocket protocol + file workflow
./scripts/run_adapter_demo.sh               # Full agent adapter chain: discover→upload→execute→download
```

| Layer | What it catches |
|-------|-----------------|
| Cliver core tests | Parser/codegen regressions; wrong code generated |
| Sample package tests | Generated driver dispatch bugs; session store issues; JSON schema errors |
| Backend tests | Upload/download protocol breaks; path routing; handle substitution |
| Adapter demo | End-to-end protocol chain; stdout pollution; JSON parse failures |

Each layer runs independently and covers a different failure mode. When a layer fails, the failure points directly at which part of the system is broken.

---

## Real example: how test layers helped locate a bug

The adapter demo layer caught a real bug: `session finished` text was leaking into stdout, causing `JSON.parse(helpResp.stdout)` to fail. This was invisible in the core tests and sample package tests — neither layer does JSON parsing. Only the end-to-end adapter demo exposed it.

Root fix: change `session finished` from `_out()` to `_err()`, so it only goes to stderr. That one-line change in codegen was found and verified because the end-to-end test existed.
