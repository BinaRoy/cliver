# Agentic Programming Setup 报告

**日期：** 2026-03-19
**项目：** Cliver（仓颉包 → WebSocket CLI driver 生成器）
**工具：** Claude Code（claude-sonnet-4-6）

---

## 1. Setup 概述

本项目采用 Claude Code 作为 agentic programming 的核心引擎，在以下范围内自主完成了从设计到实现的完整开发循环：

- 需求分析与 gap 识别
- 技术方案设计与决策对话
- 代码实现（Cangjie + Node.js）
- 测试设计与执行
- 文档更新与归档
- Git 提交与 PR 管理

---

## 2. 工具链

| 工具 | 用途 |
|------|------|
| **Claude Code CLI** | 主 agent，完成代码读写、命令执行、决策 |
| **cjpm** | 仓颉包管理器（build / test） |
| **Node.js + ws** | WebSocket backend 测试与 server 运行 |
| **Git / GitHub** | 版本控制，PR 管理 |
| **dev-journal/** | 本地知识库（设计文档、tracker、报告） |
| **cliver-tests/** | 独立测试仓库（协议测试，与实现隔离） |

---

## 3. 开发流程（实际执行的步骤）

```
需求理解 → 技术分析 → 设计文档（design.md） → 用户确认决策
    → 实现（src/ 改动） → 构建验证（cjpm build）
    → 集成测试（build_and_test.sh） → 独立协议测试（cliver-tests/）
    → Mutation 验证 → UI 测试（manual_check.js）
    → 文档更新（impl.md / tracker.md） → commit → push
```

每个 feature 遵循 `dev-journal/process/feature-workflow.md` 定义的标准流程，包含：
- Phase 0（设计）→ Phase 1（实现）→ Phase 2（验证）→ Phase 3（独立测试）→ Phase 4（收尾）

---

## 4. 成功的方面

### 4.3 测试隔离设计

独立测试仓库（`cliver-tests/`）与实现仓库分离，测试只依赖 WebSocket 协议而不依赖实现细节。这使得：
- Spec 被测试发现了 2 个错误（`path.basename("")` 返回值、EISDIR 路径边界）
- Mutation 验证有效（3/3 突变被检出）
- 测试不因实现重构而失效

### 4.4 Design doc 驱动决策

每个 feature 开发前写 `design.md`，在与用户确认关键决策（句柄命名方式、`help --json` 还是独立命令、Feature C 是否并入当前 PR）后才开始编码。避免了实现完成后需要大范围返工。

### 4.5 增量验证链

每次代码改动后执行的验证链：
```
cjpm build → PKG_SRC=... ./main（重新生成） → cjpm build（目标包）
    → cjpm test → build_and_test.sh（含 backend） → manual_check.js
```
任何一环失败立即停下排查，不积累技术债。

---

## 5. 局限与摩擦点

### 5.1 环境约束（非 Agent 能力问题）

| 问题 | 影响 | 解决方式 |
|------|------|---------|
| `cjpm run -- --pkg` 在本机无效 | 需直接调用二进制 | CLAUDE.md 记录，脚本兼容两种方式 |
| `cjpm build` 须先有 `cli_driver.cj` | 新包首次构建顺序非直觉 | 明确文档化，bootstrap 步骤固定 |
| 相对路径 `CLI_BIN` 导致 ENOENT | Server 子进程 cwd 与 shell cwd 不同 | 改为绝对路径自动探测 |

### 5.2 跨会话上下文丢失

Claude Code 的单次会话有 context window 限制，长会话被截断后需要依赖 summarization 恢复上下文。实际影响：
- 部分早期决策（如 `index.html` 是文件拷贝而非模板）需要重新发现
- 开发中间状态（如"index.html 被覆盖"）在压缩后需要重读文件

**缓解方式：** `dev-journal/` 作为外部记忆，CLAUDE.md 记录关键约束，memory 系统记录用户偏好。

### 5.3 Cangjie std.ast 解析限制

Parser 依赖 `std.ast` 解析仓颉源码，有几个已知限制：
- `break` 语句在 while 循环中导致解析失败（file-demo 初版因此报错）
- 字符级字符串下标（`content[i]`）不支持
- 泛型函数会触发错误，需跳过

Agent 在编写 file-demo 时踩中了这些限制并通过重构（改用 `.startsWith()`、`.contains()`、`.toAsciiLower()`）绕过，但花费了额外调试时间。

### 5.4 测试脚本与实现的隐式耦合

`file-demo/web/test_e2e.js` 中包含对 `greet` 函数的测试，而 file-demo 从未实现此函数，导致测试始终 2/18 失败。这是测试脚本编写时引入的 bug，与 feature 改动无关，但在 CI 中会产生误导性的失败信号。

---

## 6. Agentic Setup 的整体评估

### 适合 Agent 自主完成的任务

| 任务类型 | 效果 |
|---------|------|
| 阅读已有代码，理解架构 | 优秀——能准确识别关键约束（如 spawn 模式）|
| 按 spec 生成代码 | 优秀——生成的 JS/Cangjie 代码逻辑正确 |
| 运行并解读测试结果 | 优秀——能区分 pre-existing failure 与回归 |
| 维护设计文档 | 良好——结构清晰，决策可追溯 |
| 调试 ENOENT / 路径问题 | 良好——能定位根因（相对路径 vs 绝对路径）|

### 需要人工介入的决策点

| 决策 | 为何需要人工 |
|------|------------|
| Handle 命名方案（计数器 vs 文件名派生）| 产品偏好，无客观优劣 |
| `help --json` vs 独立 `schema` 命令 | API 设计风格选择 |
| Feature C 是否并入当前 PR | 交付节奏与范围控制 |
| gitignore 策略（哪些属于开发过程文件）| 团队规范判断 |

### 整体结论

当前 agentic setup **有效**。Agent 能够在给定约束和人工确认关键决策后，自主完成从设计到验证的完整开发循环，包括处理架构级挑战（如发现 spawn 模式导致的 handle 传递问题并重新设计）。

主要价值在于：**加速了实现-测试-调试的迭代循环**，并通过 design doc + tracker 保持了决策的可追溯性。

主要局限在于：**跨会话的记忆依赖外部文件**，以及对语言工具链（仓颉）的支持边界尚待探索。
