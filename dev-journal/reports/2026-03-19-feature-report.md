# Feature 交付报告：文件上传/下载 + 环境变量句柄

**日期：** 2026-03-19
**分支：** `feature/upload-download`
**PR：** https://github.com/BinaRoy/cliver/pull/1
**状态：** Open，待合并

---

## 1. 当前 Feature 开发结果

### 需求原文

> Add send/receive files using environment vars as a handle.

### 是否满足需求

**是，已满足。** 具体实现内容：

#### PR 包含的核心提交（共 7 个，自 `1b1aeb8` 起）

| 提交 | 内容 |
|------|------|
| `d9c3cff` | Parser/codegen 修复：跳过泛型函数，修复跨子包 import 路径 |
| `5998e95` | **核心**：WebSocket 协议扩展，新增 `upload` / `download` 消息类型，生成的 `cli_ws_server.js` 包含 `handleUpload` / `handleDownload` |
| `11e7a8b` | `index.html` 模板增加文件上传/下载 UI（左侧 sidebar、拖拽区、下载按钮） |
| `5f1af96` | 项目基础设施（dev-journal、测试框架、测试夹具） |
| `bcbae73` | 清理 `.gitignore`，移除开发过程文件 |
| `df20c22` | 修复 UI 回归（恢复原有 CSS/JS 行为，仅新增部分不减旧功能） |
| `fe56c22` | **环境变量句柄**：`upload_result` 增加 `handle` 字段；`help --json` 结构化输出 |

#### 关键设计

**上传流程（环境变量句柄）：**

```
Agent/User 上传文件
    → { type: "upload", filename: "data.csv", data: "<base64>" }
    ← { type: "upload_result", path: "/tmp/cliver/uploads/...", handle: "DATA_CSV" }

Agent/User 在命令中使用句柄
    → { line: "lineCount $DATA_CSV" }
    （server 在转发给 CLI 进程前将 $DATA_CSV 替换为实际路径）
    ← { stdout: "3 lines" }
```

**句柄命名规则：**
- 取文件名（不含扩展名）→ 全大写 → 非字母数字替换为 `_`
- 例：`my-data.csv` → `MY_DATA`，`report (v2).pdf` → `REPORT__V2_`
- 同一 session 内同名冲突：自动加 `_2`、`_3` 后缀

**下载流程：**

```
Agent/User 请求下载
    → { type: "download", path: "/tmp/cliver/uploads/..." }
    ← { type: "download_result", filename: "out.txt", data: "<base64>" }
```

**`help --json`（新增，供 Agent 发现命令 schema）：**

```
→ { line: "help --json" }
← { stdout: '{"commands":[{"name":"lineCount","packagePath":"/","returnType":"String","params":[{"name":"path","type":"String"}],...}],"builtins":["echo","dir","help","cd"]}' }
```

#### 安全约束

- 上传：文件名经 `path.basename()` + 正则清洗，UUID 前缀防冲突
- 下载：路径经 `path.resolve()` 规范化后检查是否在 `/tmp/cliver/` 下；路径穿越攻击被阻断
- 句柄：仅在 server 层替换，CLI 进程不接触原始句柄名

---

## 2. Feature 验证思路与结果

### 2.1 人工使用（Web UI）

**启动方式：**

```bash
cd file-demo   # 或任意 Cliver 生成的包
node web/cli_ws_server.js
# 浏览器打开 http://localhost:8765
```

**操作流程与预期结果：**

| 操作 | 预期结果 |
|------|---------|
| 拖拽本地文件到左侧 Files 区域 | 左侧列表出现文件条目，显示 `$FILENAME`（不显示长路径） |
| 点击"Insert"按钮 | 命令输入框光标处插入 `$FILENAME` |
| 输入 `lineCount $FILENAME`，Shift+Enter | 返回文件行数（server 自动替换了句柄） |
| 输入 `help --json`，Shift+Enter | 返回 JSON 格式命令列表 |
| 输入 `toUpperCase $FILENAME /tmp/cliver/uploads/out.txt` | 返回输出路径；输出框内出现 `⬇ out.txt` 按钮 |
| 点击 `⬇ out.txt` 按钮 | 浏览器触发下载，内容为大写文本 |
| 上传第二个同名文件 | 列表出现 `$FILENAME_2`，两个句柄互不干扰 |

### 2.2 Agent 视角（工具 / OpenClaw 类框架）

**验证方式：** `manual_check.js` — 单持久连接，模拟 agent 的完整 session 行为

```bash
node web/cli_ws_server.js &
PORT=9877 node web/manual_check.js
```

**验证覆盖的 7 个场景：**

| # | 场景 | 结果 |
|---|------|------|
| 1 | `help` 返回可读命令列表 | ✓ |
| 2 | `help --json` 返回合法 JSON schema，含 params/returnType | ✓ |
| 3 | 上传文件 → `upload_result` 含 `path` + `handle`（`$SAMPLE`）| ✓ |
| 4 | 同一 session 中用 `$SAMPLE` 调用命令，server 正确替换并执行 | ✓ |
| 5 | 同一 session 再传同名文件 → `$SAMPLE_2`（冲突处理正确）| ✓ |
| 6 | 下载文件 → base64 round-trip 内容完全匹配 | ✓ |
| 7 | 下载 `/etc/passwd` → `Access denied`（安全阻断）| ✓ |

**结论：7/7 全部通过。**

集成测试（`test_backend.js`）和单元测试（`cjpm test`）也全部通过。

---

## 3. 与 OpenClaw 的对接：现状与后续规划

### 3.1 当前已满足的条件

| 条件 | 状态 | 说明 |
|------|------|------|
| WebSocket 通信协议 | ✅ | 纯 JSON，任何语言可实现客户端 |
| 文件上传到 server | ✅ | base64 编码，支持任意文件类型 |
| 环境变量句柄 | ✅ | `$HANDLE` 在 server 层透明替换 |
| 文件下载 | ✅ | base64 返回，可落盘或直接处理 |
| 命令 schema 发现 | ✅ | `help --json` 返回结构化命令列表 |
| 安全约束 | ✅ | 路径穿越防护，文件名清洗 |

一个 OpenClaw adapter 需要的底层能力**已全部就绪**。

### 3.2 后续需要开发的框架

按依赖顺序：

#### Phase 1（已计划，单独 PR）：OpenClaw 参考适配层

目标：一个独立脚本，证明从 agent framework 到 Cangjie 函数的完整链路可行。

```
OpenClaw tool-call
    → adapter: 解析 tool schema，映射到 Cliver 命令
    → WebSocket: 发送 { line: "..." } 或 upload/download
    → Cliver WS server → CLI 二进制 → Cangjie 函数
    ← 返回结果，适配为 tool-call response
```

需要开发：
- **Schema 映射**：`help --json` 输出 → OpenClaw tool definition 格式（`name`, `description`, `parameters` JSON Schema）
- **Session 管理**：每个 agent task 复用同一 WebSocket session（句柄生命周期对齐）
- **文件生命周期**：upload 在 task 开始时执行，task 结束后可选清理
- **错误映射**：`download_error` / `upload_error` → tool-call error response

#### Phase 2（未来）：生产级集成

- WebSocket session 池（多 agent 并发）
- 文件自动清理（session 关闭时删除 `/tmp/cliver/uploads/<session>/`）
- 流式上传（大文件分片）
- `help --json` 扩展：加入参数描述（`description` 字段，供 agent LLM 理解语义）

### 3.3 可行性分析

**高可行性。** 核心论据：

1. **协议简单**：纯 JSON over WebSocket，没有特殊依赖。任何支持 WebSocket 的 agent 框架可以直接对接，无需 SDK。

2. **schema 已可机读**：`help --json` 已输出 `name/params/returnType`。从这里到 OpenClaw tool definition 的 gap 只是字段映射（约 30-50 行适配代码）。

3. **文件传输已验证**：上传→句柄→命令→下载的完整链路已通过 `manual_check.js` 端到端验证，等价于 agent 的实际调用模式。

4. **主要风险**：
   - OpenClaw 的具体 tool-call API 格式需要对照文档适配（未知量）
   - 当前无 `description` 字段 → agent LLM 无法理解命令语义（可后续在 Cangjie 注释中提取）
   - 并发多 session 未测试（单进程 Node.js 理论支持，需压测）

**结论：** 当前状态下，写一个可工作的 OpenClaw demo adapter 估计需要 1-2 天工作量，主要在 schema 映射和 session 管理。生产级集成需额外处理并发和文件清理，但不存在架构障碍。
