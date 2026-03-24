# Cliver Agent-Ready Demo Runbook

## Goal

This demo is meant to prove one specific claim:

**Agents like OpenClaw can hook up to Cangjie packages through cliver, discover package capabilities, invoke them through a cliver-generated interface, and complete an upload -> process -> download workflow.**

This is **not** just a web UI demo.

The proof points are:

1. `help --json` exposes machine-readable command discovery.
2. The command is available through a **cliver-generated** CLI driver.
3. An uploaded file path is passed into a Cangjie package command.
4. The package writes a result file under `/tmp/cliver/`.
5. The result is downloaded in the same workflow.

---

## Demo Scope

The sample package includes a minimal command:

- `buildUploadReport(inputPath: String): String`

What it does:

- reads the uploaded input file
- computes a few simple facts about the content
- writes a report file to `/tmp/cliver/outputs/`
- returns the output path so it can be downloaded

This is intentionally minimal. The point is to prove the integration path, not to show a complicated business workflow.

---

## Demo Preflight

Run these commands before the audience joins.

From the repo root:

```bash
cd /home/gloria/tianyue/cliver
cjpm build
PKG_SRC=/home/gloria/tianyue/cliver/sample_cangjie_package ./target/release/bin/main
cd /home/gloria/tianyue/cliver/sample_cangjie_package
cjpm build
node web/cli_ws_server.js
```

Open this page in a browser:

```text
http://localhost:8765/
```

Optional verification before the live demo:

```bash
cd /home/gloria/tianyue/cliver/sample_cangjie_package
cjpm test -V
node test_backend.js
```

Expected result:

- the backend prints `WebSocket on ws://localhost:8765`
- the browser page loads
- the sample package has a generated CLI driver

How to explain it:

- “I already built cliver, generated the driver for the sample Cangjie package, and started the browser backend.”

---

## Input File To Prepare

Create a small local file named `demo-input.csv` with this content:

```text
name,score
Alice,100
Bob,95
```

Expected result:

- this file will be uploaded into `/tmp/cliver/uploads/...`

How to explain it:

- “The agent workflow starts with a real input artifact, not a fake hardcoded string.”

---

## Live Demo Steps

## Step 1: Prove Command Discovery

In a terminal, run:

```bash
cd /home/gloria/tianyue/cliver/sample_cangjie_package
./target/release/bin/main "help --json"
```

Expected result:

- stdout contains a JSON object with `commands`
- one of the entries is:

```json
{"name":"buildUploadReport","commandKind":"function","packagePath":"/","returnType":"String","params":[{"name":"inputPath","type":"String","role":"path"}]}
```

What to say:

- “This is the machine-readable capability surface.”
- “An agent does not need handwritten glue docs to know what the package can do.”
- “The command list and parameter schema are coming from the cliver-generated interface.”

---

## Step 2: Upload A File In The Browser

In the page:

1. drag `demo-input.csv` into the upload area, or click to select it
2. wait for the upload item to appear

Expected result:

- the UI shows an uploaded file entry
- it shows a server-side path under `/tmp/cliver/uploads/`
- it also shows a handle derived from the file name, typically `$DEMO_INPUT`

What to say:

- “Upload is not the proof by itself.”
- “What matters is that the workflow now has a concrete server-side file path that the package can consume.”

---

## Step 3: Show Discovery In The Same Agent Surface

In the browser input box, type:

```text
help --json
```

Expected result:

- the browser output shows the same machine-readable command schema
- `buildUploadReport` appears with parameter `inputPath`

What to say:

- “This is the discovery path an agent would use inside the same operational surface.”

---

## Step 4: Invoke The Package Capability

In the browser input box, type:

```text
buildUploadReport $DEMO_INPUT
```

If the handle shown by the UI is different, use that handle instead.  
If needed, you can also paste the full uploaded path shown in the upload panel:

```text
buildUploadReport /tmp/cliver/uploads/<actual-uploaded-file>
```

Expected result:

- the command succeeds
- output contains a path under `/tmp/cliver/outputs/`
- the path looks like:

```text
/tmp/cliver/outputs/<uploaded-file-name>.report.txt
```

What to say:

- “This is the key proof point.”
- “The uploaded file path is now being passed into a Cangjie package command.”
- “The command is exposed through the cliver-generated interface, not through a custom one-off backend endpoint.”
- “The package itself produces a new artifact for downstream use.”

---

## Step 5: Download The Result

In the browser:

1. find the output line that contains the `/tmp/cliver/outputs/...` path
2. click the download button or download hint shown for that path

Expected result:

- the browser downloads the generated report file

Open the downloaded file. It should contain content like:

```text
INPUT_PATH=/tmp/cliver/uploads/demo-input.csv
BYTE_COUNT=28
CHAR_COUNT=28
LINE_COUNT=3
UPPERCASE_PREVIEW=NAME,SCORE
```

What to say:

- “This completes the same workflow: upload -> invoke package capability -> generate output artifact -> download.”
- “That is the practical value of connecting an agent to a Cangjie package through cliver.”

---

## Short Narration Script

If you want a compact version for a manager demo, use this:

1. “First I’ll show that the package is agent-discoverable through `help --json`.”
2. “Next I upload a real file so the workflow has a concrete artifact.”
3. “Then I invoke a package command that cliver exposed automatically.”
4. “The package processes the uploaded file and writes a result under `/tmp/cliver/`.”
5. “Finally I download that result, which proves upload and download are in the same real workflow.”

---

## Expected Takeaway

By the end of the demo, the audience should believe all of these:

- cliver can generate an agent-usable interface for a Cangjie package
- agents can discover commands and parameters through `help --json`
- uploaded files can become package inputs
- package outputs can become downloadable artifacts
- this is a real workflow, not just a page with buttons

---

## Current Limits And Risks

- The sample command is intentionally simple. It proves integration, not business complexity.
- The browser workflow depends on the Node WebSocket backend being up.
- Convenient handle substitution like `$DEMO_INPUT` is session-scoped. If it is unclear, use the absolute uploaded path shown in the UI.
- Session wrapper text (`lesson_demo session finished`) is now written to stderr only and does not appear in command output.
- The demo assumes local `cjc`, `cjpm`, and Node are correctly installed.

---

## Files Relevant To This Demo

- [README.md](/home/gloria/tianyue/cliver/README.md)
- [sample_cangjie_package/src/main.cj](/home/gloria/tianyue/cliver/sample_cangjie_package/src/main.cj)
- [sample_cangjie_package/src/cli_driver.cj](/home/gloria/tianyue/cliver/sample_cangjie_package/src/cli_driver.cj)
- [sample_cangjie_package/test_backend.js](/home/gloria/tianyue/cliver/sample_cangjie_package/test_backend.js)
- [docs/demo-runbook.md](/home/gloria/tianyue/cliver/docs/demo-runbook.md)
