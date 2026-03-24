---
feature: agent-backend-hardening
spec_version: 0.1
date: 2026-03-23
status: final
---

# Agent Backend Hardening — Design Draft

## Background

截至 `2026-03-23`，仓库已经证明：

- `help --json` 可做基础 command discovery
- upload/download WebSocket 协议可用
- sample package 已有 `buildUploadReport` 文件工作流 demo
- `agent-adapter-demo` 已证明 `discover -> upload -> execute -> download` 完整协议链

但当前证据仍然主要集中在：

- generated Node backend
- browser / WebSocket protocol path
- 人工可演示的端到端链路

还没有把 cliver 完整提升为更稳的 agent/backend integration layer。

---

## Goal

本 feature 的目标是把当前“可演示”状态推进到“更适合作为 backend integration layer 持续开发”的状态。

它不是新增一条产品线，而是对现有 agent/back-end 方向做补强。

---

## Task Breakdown

### Task 1 — 最小 in-process backend/session proof

**目标：**
证明 `runFromArgs(args, store, nextId)` 可以被一个长生命周期 session/backend 复用，而不是只能在每次 CLI 进程中重置状态。

**当前缺口：**
- 现在的强证据来自 Node/WebSocket 路径
- 还没有一个最小 in-process/session demo 持有 `store + nextId`

**完成标准：**
- 有一个最小 session demo
- 同一 session 内至少两次调用 `runFromArgs()`
- 能观察到 `nextId` / object store 跨调用延续

---

### Task 2 — `help --json` schema enrich

**目标：**
把现有 discovery schema 从“基础可用”提升到“更适合 agent planning”。

**当前缺口：**
- 现在只有 `name / packagePath / returnType / params(name,type)`
- 没有表达参数角色和 artifact 语义

**期望补充字段：**
- param role：`path` / `ref` / `plain`
- return role：是否为 artifact path
- command kind：builtin / constructor / function / method

---

### Task 3 — 共享整行执行层

**目标：**
统一 `main()` 和 `runFromArgs()` 的语义来源，避免未来 backend 重写 line-level 逻辑。

**当前缺口：**
- `main()` 处理 `;`、`NAME = command`、`$NAME`
- `runFromArgs()` 只处理 argv

**完成标准：**
- 存在共享执行层（例如 `runLine(...)` / `runSegments(...)`）
- CLI 和未来 backend 共用该层

---

### Task 4 — 将 adapter demo 纳入自动验证

**目标：**
把当前主要依赖人工验收的 adapter demo 变成回归测试的一部分。

**当前缺口：**
- `agent-adapter-demo` 已完成，但验收门槛仍主要是人工运行

**完成标准：**
- 至少一条自动化测试或脚本能验证 adapter 协议链
- 文档记录其运行方式和通过标准

---

### Task 5 — 清理 machine-readable 输出协议

**目标：**
减少 wrapper text / string scraping，让 agent 更稳定地消费结果。

**当前缺口：**
- 当前命令输出仍可能混入 session 结束类文本

**完成标准：**
- command result、stderr、session meta、artifact path 的边界更清晰

---

## Dependency Order

推荐顺序：

1. Task 1 — 最小 in-process backend/session proof
2. Task 2 — `help --json` schema enrich
3. Task 3 — 共享整行执行层
4. Task 4 — adapter demo 自动验证
5. Task 5 — 输出协议清理

理由：

- Task 1 是当前最关键的证据缺口
- Task 2 和 Task 3 会直接影响 backend 接入质量
- Task 4 用于把当前 demo 证据固化为回归门槛
- Task 5 是体验和协议稳定性增强

---

## Affected Areas

| 区域 | 可能涉及 |
|------|----------|
| generated driver | `src/codegen.cj` |
| backend template | `src/main.cj` |
| sample package verification | `sample_cangjie_package/src/cli_driver_test.cj`, `sample_cangjie_package/test_backend.js` |
| agent demo | `dev-journal/features/2026-03-23-agent-adapter-demo/` 与 `cliver-tests/demo/` |
| docs | `docs/development.md`, `docs/TESTING.md`, `docs/browser-terminal-actors.md`, `docs/generated-driver.md`, `docs/api-reference.md` |

---

## Out of Scope

本 feature 暂不处理：

- 生产级 agent framework 适配
- 多语言 adapter 扩展
- 并发上传/并发 session 优化
- 文件大小限制与 streaming

这些都应放在后续独立 feature 中处理。
