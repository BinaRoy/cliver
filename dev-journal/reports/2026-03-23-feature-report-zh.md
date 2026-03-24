## 做了什么

这条 feature 在已有 CLI 生成器的基础上增加了三件事：

**1. 文件传输协议（WebSocket）**

生成的 Node.js backend 新增两种消息类型：

```
{ type: "upload", filename: "demo.txt", data: "<base64>" }
→ { type: "upload_result", path: "/tmp/cliver/uploads/demo.txt", handle: "$DEMO" }

{ type: "download", path: "/tmp/cliver/outputs/demo.txt.report.txt" }
→ { type: "download_result", data: "<base64>" }
```

上传文件存入 `/tmp/cliver/uploads/`，package 生成的输出文件在 `/tmp/cliver/outputs/` 下可供下载。Backend 在派发命令行之前把 `$HANDLE` 替换为实际上传路径，调用方不需要自己追踪完整路径。

**2. Sample package 中的真实文件处理命令**

`sample_cangjie_package/src/main.cj` 新增 `buildUploadReport(inputPath: String): String`：

- 读取 `inputPath` 指向的文件
- 计算行数、字符数、首行大写预览
- 把 `.report.txt` 写入 `/tmp/cliver/outputs/`
- 返回输出路径字符串

这让 sample package 真正参与文件工作流，而不只是一个演示类结构的玩具。

**3. Agent 友好的生成 driver 增强**

`agent-backend-hardening` 工作（同一分支）完成后，生成的 `cli_driver.cj` 还包含：

- `help --json` 现在对每条命令输出 `commandKind`（`"constructor"` / `"function"` / `"method"`），对每个参数输出 `role`（`"path"` / `"ref"` / `"plain"`）。当前生成 driver 的实际例子：

  ```json
  {"name":"buildUploadReport","commandKind":"function","packagePath":"/","returnType":"String",
   "params":[{"name":"inputPath","type":"String","role":"path"}]}
  ```

  ```json
  {"name":"Student","commandKind":"constructor","packagePath":"/","returnType":"Student",
   "params":[{"name":"name","type":"String","role":"plain"},{"name":"id","type":"Int64","role":"plain"}]}
  ```

- Instance method（如 `Student getName`、`Student setName`）现在也出现在 schema 里，带有 `className` 和 `commandKind: "method"`。

- `session finished` 文本只写到 stderr，命令的 stdout 输出干净。

- `_runLine()` 是一个共享执行层，`_serveStdin()` 和 `main()` 都调用它。`;` 分隔命令、`NAME=cmd` 赋值、`$NAME` 替换在 CLI 路径和 WebSocket 路径上行为完全一致。

---

## 测试结果

| 测试套件 | 数量 | 结果 |
|---------|------|------|
| Cliver core（`cjpm test`） | 16 | ✓ 全部通过 |
| Sample package（`cjpm test`） | 16 | ✓ 全部通过 |
| Backend 协议（`node test_backend.js`） | upload→exec→download 链路 | ✓ 通过 |
| Adapter demo（`scripts/run_adapter_demo.sh`） | exit 0 | ✓ 自动化验证 |

Sample package 的 16 个测试中包含：
- `buildUploadReportCreatesDownloadableFileUnderTmpCliver`：向 `/tmp/cliver/outputs/` 写入真实文件，断言内容
- `sessionStoreAndInstanceMethodsWorkAcrossMultipleCalls`：用同一个 `store` 跨多次 `runFromArgs()` 调用，证明创建 → 读取 → 修改 → 再读取对象状态正确持久
- `helpJsonIncludesCommandListAndFileProcessorSchema`：断言 JSON 输出中包含 `commandKind`、`role`、`className` 字段

---

## Demo

完整工作流可以通过两种方式运行：

**自动化（脚本）：**
```bash
./scripts/run_adapter_demo.sh
```
脚本启动 WebSocket server，运行 `cliver-tests/demo/agent-adapter.js`（一个 Node.js 客户端，自动完成 discover → upload → execute → download），exit 0 即通过。

**手动（浏览器）：**
```bash
# 从仓库根目录
cjpm build
PKG_SRC=sample_cangjie_package ./target/release/bin/main
cd sample_cangjie_package && cjpm build
node web/cli_ws_server.js
# 打开 http://localhost:8765
```
步骤：调用 `help --json` → 上传文件 → 运行 `buildUploadReport $HANDLE` → 点击输出路径旁的下载按钮。

两种方式都要展示的核心证据链：
1. `help --json` 返回带 `commandKind` 和 `role` 的机器可读 schema。Agent 通过它知道 package 有哪些能力，每个参数是什么类型的输入。
2. 上传一个文本文件 → backend 分配路径和 `$HANDLE`。
3. 运行 `buildUploadReport $HANDLE` → Cangjie package 读取文件，把 report 写到 `/tmp/cliver/outputs/`。
4. 下载输出路径 → 调用方取回结果文件。

这条链路证明的不是"页面可以点"，而是：**upload/download 是外部调用方和 Cangjie package 代码之间真实的数据交接。**

---

## 为什么它可以接上 OpenClaw 这类 Agent

Agent 需要四个条件才能使用一个 backend 工具：

| 条件 | Cliver 的提供方式 |
|------|-----------------|
| 发现有哪些命令、参数是什么含义 | `help --json`，带 `commandKind` + 参数 `role` |
| 把文件作为输入送进去 | 上传协议 → 服务端路径 + handle |
| 调用 package 能力 | WebSocket `{ line: "cmd arg1 arg2" }` 或 in-process `runFromArgs()` |
| 取回生成的输出文件 | 按路径下载协议 |

`cliver-tests/demo/agent-adapter.js` 是这套流程的一个实际实现：它调用 `help --json`，上传文件，用 handle 运行 `buildUploadReport`，从 stdout 读取输出路径，再下载结果。全程无人工干预，通过。

关键区别：adapter 脚本没有 UI，它是一个程序在调用另一个程序。这和 agent 调用 backend 工具的拓扑结构完全一样。

开发过程中沉淀的 workflow 和测试层次见：[2026-03-23-dev-workflow-zh.md](./2026-03-23-dev-workflow-zh.md)
