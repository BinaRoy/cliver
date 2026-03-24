---
feature: agent-backend-hardening
status: Verified
date_verified: 2026-03-23
---

# Agent Backend Hardening — Implementation Notes

## Status

**Verified** — commit `43f59aa` ("agent-backend-hardening: Tasks 1-5 implementation")

全部 5 个 task 已在一次 commit 内完成。16 个单元测试 + 16 个集成测试通过。

---

## Task 1 — 最小 in-process backend/session proof

**实现位置：** `sample_cangjie_package/src/cli_driver_test.cj`

新增测试用例 `sessionStoreAndInstanceMethodsWorkAcrossMultipleCalls`：

```cj
let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
let r1 = runFromArgs(["Student", "new", "Alice", "1001"], store, 1)
// ref:1 存入 store, nextId=2
let r2 = runFromArgs(["Student", "getName", "ref:1"], store, r1.nextId)
// stdout 包含 "Alice"
let r3 = runFromArgs(["Student", "setName", "ref:1", "Bob"], store, r2.nextId)
// exitCode == 0
let r4 = runFromArgs(["Student", "getName", "ref:1"], store, r3.nextId)
// stdout 包含 "Bob"
```

证明：同一个 `store` HashMap 在多次 `runFromArgs()` 调用之间持久，object store 和 `nextId` 正确跨调用延续。

---

## Task 2 — `help --json` schema enrich

**实现位置：** `src/codegen.cj`（`_printHelpJson()` 生成段）

新增字段：

- **`commandKind`**：`"constructor"` / `"function"` / `"method"` / `"staticMethod"`
- **`role`**（每个 param）：`"ref"` / `"path"` / `"plain"`
  - `ref`：paramType 是已知 class 名（当前 manifest 中的 className）
  - `path`：paramType 为 String 且 paramName 含 path/file/dir/input/output 关键词
  - `plain`：其余
- **`className`**：仅 instance method 输出，标明所属类
- 类的 instance methods 现在也包含在 JSON schema 中（之前 `help --json` 只列出 constructor 和 function）

新增辅助函数：
- `_commandKindStr(cmd: CommandInfo): String`
- `_paramRoleStr(paramName, paramType, classNamesList): String`

测试断言（`helpJsonIncludesCommandListAndFileProcessorSchema`）：
- `"commandKind":"function"`, `"commandKind":"constructor"`, `"commandKind":"method"`
- `"role":"path"`, `"role":"ref"`
- `"className":"Student"`

---

## Task 3 — 共享整行执行层

**实现位置：** `src/codegen.cj`（生成的 `_runLine()` 函数）

提取 `_runLine(line: String, env: HashMap<String, String>, outBuf: StringBuilder): Int64`：

- 内含完整 `;` 分隔段处理、`NAME=cmd` 赋值、`$NAME` 替换语义
- `_serveStdin()` 和 `main()` 两处原有重复循环（各约 35 行）均改为调用 `_runLine()`
- CLI path 和 WebSocket session path 现在共享完全相同的行级执行语义

意义：此前 `main()` 和 `_serveStdin()` 各自独立实现 `;`/`$NAME` 逻辑，未来如有新 backend 接入无需重复实现。

---

## Task 4 — adapter demo 自动验证

**实现位置：** `scripts/run_adapter_demo.sh`

脚本行为：
1. 检查 `cli_ws_server.js`、`cliver-tests/demo/agent-adapter.js`、CLI binary 是否存在
2. 在后台启动 `cli_ws_server.js`，绑定 `$PORT`（默认 18765）
3. 运行 `agent-adapter.js`，验证 exit 0
4. 无论成败都 kill server（`trap cleanup EXIT`）

支持的环境变量：`CLIVER_REPO`, `CLIVER_TESTS_REPO`, `PORT`, `CLI_BIN`, `CANGJIE_ENVSETUP`

运行方式：
```bash
./scripts/run_adapter_demo.sh
# 或跨仓
CLIVER_TESTS_REPO=/path/to/cliver-tests ./scripts/run_adapter_demo.sh
```

---

## Task 5 — machine-readable 输出协议清理

**实现位置：** `src/codegen.cj`（`_serveStdin()` 和 `main()` 生成段）

变更：将 `_outNoNewline("pkg session finished")` 改为 `_err("pkg session finished")`

两处修改（WebSocket path 和 CLI main path 各一处）：
- 修改前：`session finished` 出现在 stdout，混入 command output
- 修改后：`session finished` 只出现在 stderr，command result 在 stdout 中干净

背景：`agent-adapter.js` 中 `JSON.parse(helpResp.stdout)` 和输出路径提取均因此文本污染而失败，改到 stderr 后 demo 无需防御性 parsing 即可稳定运行。

---

## Known Constraints

- 必须保留 `dev-journal` 作为唯一确认入口
- 不新增平行入口文档
- 进度应通过 feature / tracker 更新，而不是通过新的全局指针分流
