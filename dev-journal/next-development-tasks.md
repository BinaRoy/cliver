# Next Development Tasks

**用途：** 这是下一次开发的任务入口。  
**使用方式：** 新 session 开始时，先读 [AGENT.md](AGENT.md)，再读本文件，确认本轮要推进的 task。

---

## 当前判断

截至 `2026-03-23`，仓库已经具备：

- `help --json` command discovery
- upload/download WebSocket protocol
- sample package 文件处理 demo（`buildUploadReport`）
- Node.js adapter demo，证明 `discover -> upload -> execute -> download` 完整协议链
- 实现仓与 sample/backend 测试绿灯

但还存在几个**下一阶段开发任务**，它们不再是“能不能 demo”的问题，而是“能不能把 cliver 从 demo 工具提升成更稳的 agent integration layer”的问题。

---

## Task 总览

| Priority | Task | 当前状态 | 为什么还要做 |
|----------|------|----------|--------------|
| P0 | 最小 in-process backend/session proof | 未做 | 现在只证明了 WebSocket 路径，还没证明 `runFromArgs()` 能作为真正 backend 接口稳定接入 |
| P1 | `help --json` schema enrich | 基础版已完成 | 现在 discovery 可用，但信息仍偏薄，不利于 agent 做稳定 tool planning |
| P1 | 共享整行执行层（`runLine` / `runSegments`） | 未做 | 现在 `main()` 和 `runFromArgs()` 语义未统一，未来 backend 接入会重复实现或丢语义 |
| P1 | 把 agent-adapter-demo 纳入自动验证 | 未做 | 现在 adapter demo 主要是人工验收，不能作为长期回归门槛 |
| P2 | 清理 machine-readable 输出协议 | 未做 | 当前仍有 wrapper text，agent 消费要额外做字符串清洗 |

---

## Task 1 — 最小 in-process backend/session proof

**Priority:** P0

### 为什么要做

当前仓库已经证明：

- package 可以通过 cliver 暴露成命令
- backend 可以做 upload/download
- Node.js adapter 可以跑完整协议链

但还没有证明：

- `runFromArgs(args, store, nextId)` 可以被一个长生命周期 backend/session 真正持有和复用

这仍然是 cliver 从 “web demo tool” 走向 “agent integration layer” 的关键一跳。

### 当前状态

- 已有 `runFromArgs()` 入口
- 已有 Node backend
- 已有 adapter demo
- 尚无一个最小 session backend 示例持有 `store + nextId`

### 证据

- `src/codegen.cj` 生成 `runFromArgs()`
- `docs/browser-terminal-actors.md` 明确把 actors/in-process backend 作为下一层方向
- `docs/limitations-and-future.md` 仍指出 library path 与 full-line semantics 未完全统一

### Definition of done

- 有一个最小 backend/session demo
- 在同一 session 内连续调用 `runFromArgs()` 至少两次
- 能证明 session state（store / nextId）不是每次重置
- 有对应文档和最少一条可重复验证命令

### 相关文件

- `src/codegen.cj`
- `docs/browser-terminal-actors.md`
- `dev-journal/features/2026-03-19-agent-integration/`

---

## Task 2 — `help --json` schema enrich

**Priority:** P1

### 为什么要做

`help --json` 现在已经可用，但对 agent 来说还缺少更强的 planning 信息。
下一步不是“补一个 help --json”，而是把已有 schema 提升成更像 tool contract 的格式。

### 当前状态

已支持：

- command name
- packagePath
- returnType
- param name / type
- builtins

缺少：

- 参数角色：`path` / `ref` / `plain`
- 返回值是否是 artifact path
- command kind：builtin / constructor / package func / method
- 可选的 description / example

### 证据

- `src/codegen.cj` 已有 `_printHelpJson()`
- `sample_cangjie_package/src/cli_driver_test.cj` 已验证 `help --json` 包含 `buildUploadReport`
- 当前 schema 仍不足以直接表达“这个命令适合接文件路径，并可能产出下载文件”

### Definition of done

- `help --json` 增加最少一层语义字段
- sample test 覆盖新 schema
- 文档明确字段语义

### 相关文件

- `src/codegen.cj`
- `docs/generated-driver.md`
- `docs/api-reference.md`
- `sample_cangjie_package/src/cli_driver_test.cj`

---

## Task 3 — 共享整行执行层

**Priority:** P1

### 为什么要做

当前：

- `main()` 处理整行语义：`;`、`NAME = command`、`$NAME`
- `runFromArgs()` 只处理 argv 级调用

这导致未来任何 in-process backend 都要么：

- 自己重写 line parsing
- 要么失去 CLI 当前已有的整行语义

### 当前状态

- Node backend 还能工作，因为它把整行交给 `main()`
- in-process backend 若直接走 `runFromArgs()`，语义就会缩水

### 证据

- `docs/limitations-and-future.md` 已记录这个限制
- `docs/browser-terminal-actors.md` 已描述两条调用路径不完全一致

### Definition of done

- 生成 driver 中存在可复用的 `runLine(...)` 或等价共享层
- `main()` 与未来 backend 复用同一语义层
- 对 `;`、`NAME = command`、`$NAME` 至少有一组回归测试

### 相关文件

- `src/codegen.cj`
- `sample_cangjie_package/src/cli_driver_test.cj`
- `docs/browser-terminal-actors.md`
- `docs/limitations-and-future.md`

---

## Task 4 — 把 agent-adapter-demo 纳入自动验证

**Priority:** P1

### 为什么要做

当前 adapter demo 已经是很强的证据，但主要是人工验收。
如果它不进入自动验证，就很容易在后续改动里变成“文档存在、但链路失效”。

### 当前状态

- `dev-journal/AGENT.md` 已把 adapter demo 记为已完成
- `dev-journal/features/2026-03-23-agent-adapter-demo/` 已有 design / impl / tracker
- 自动测试层面仍没有把它作为回归门槛

### 证据

- `agent-adapter-demo/tracker.md` 已明确“无自动测试，人工验收为接受门槛”
- 当前 testing docs 还没有把 adapter demo 作为 CI/本地回归的一层

### Definition of done

- 在 `cliver-tests/` 或等价测试入口中增加 adapter demo 自动验证
- 本地可以一条命令跑
- 测试文档记录此层的目的和执行方式

### 相关文件

- `dev-journal/features/2026-03-23-agent-adapter-demo/`
- `dev-journal/process/testing-strategy.md`
- `docs/TESTING.md`

---

## Task 5 — 清理 machine-readable 输出协议

**Priority:** P2

### 为什么要做

当前系统可用，但输出里仍可能混入 wrapper text，比如 session finished。
这对 demo 问题不大，对 agent 稳定消费不够理想。

### 当前状态

- WebSocket 返回结构化 JSON
- 但 command 输出内容仍需要调用方做少量清洗/提取

### 证据

- backend 测试中需要对 stdout 做字符串匹配和路径提取
- 当前协议还没有 artifact-specific envelope

### Definition of done

- 明确区分 command stdout、stderr、session meta、artifact path
- 降低调用方的字符串 scraping 需求

### 相关文件

- `src/main.cj`
- `sample_cangjie_package/test_backend.js`
- `docs/browser-terminal-actors.md`

---

## 下一次开发建议顺序

1. Task 1 — 最小 in-process backend/session proof
2. Task 2 — `help --json` schema enrich
3. Task 3 — 共享整行执行层
4. Task 4 — adapter demo 自动验证
5. Task 5 — 输出协议清理

---

## 下一次开发前必读

1. [AGENT.md](AGENT.md)
2. [process/feature-workflow.md](process/feature-workflow.md)
3. [process/testing-strategy.md](process/testing-strategy.md)
4. 本文件

如果下一次开发要单独立 feature，请按 `process/feature-workflow.md` 新建：

- `design.md`
- `impl.md`
- `tracker.md`

建议优先把 **Task 1** 作为下一个正式 feature。
