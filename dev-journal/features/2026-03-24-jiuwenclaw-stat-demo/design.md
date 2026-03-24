---
feature: jiuwenclaw-stat-demo
spec_version: 0.1
date: 2026-03-24
status: draft
---

# JiuwenClaw × Cliver 统计计算 Demo — 方案整理

## 背景与目的

本方案的核心论点：**agent 不擅长（或成本过高）的数值计算，可以通过 Cliver 卸载给仓颉实现。**

具体来说：
- Agent 处理大 CSV 消耗大量 token；矩阵运算精度差；统计算法实现慢
- 仓颉实现的统计函数经过编译，精确、快速
- Cliver 将仓颉 public func 暴露为 CLI 命令，无需编译出 SDK，agent 直接通过 WebSocket 调用

---

## 集成架构

```
用户 → JiuwenClaw Agent
           │
           ├─[初始化，一次性]
           │    shell: PKG_SRC=<stat_demo包路径> ./cliver_binary
           │    → 生成 stat_demo/src/cli_driver.cj
           │    shell: cd stat_demo && cjpm build
           │    shell: node stat_demo/web/cli_ws_server.js  (保持运行)
           │
           └─[运行时，每次对话]
                WebSocket 连接（单连接持续整个 session）
                │
                ├─→ { line: "help --json" }              // 发现可用函数
                ├─→ { type: "upload", filename, data }   // 上传数据文件（base64）
                │   ← { type: "upload_result", path, handle }
                ├─→ { line: "summarize $HANDLE" }        // 调用统计函数
                │   ← { stdout: "{ ... json ... }" }
                └─→ { type: "download", path }           // 下载结果文件（如有）
                    ← { type: "download_result", data }
```

### 为什么选 WebSocket 而不是 shell subprocess

1. **Session 状态**：object store（`ref:1`, `ref:2`...）只在单个 WebSocket 连接内持续，链式操作需要长连接
2. **文件传输已内置**：upload/download 协议已在 `cli_ws_server.js` 实现，shell 替代需要重新设计文件传输
3. **Agent 框架天然异步**：WebSocket 消息模型与 agent 的 I/O 模型匹配，shell subprocess 管理更复杂

Shell 调用只用于**一次性初始化**（cliver 生成 driver + cjpm build），不是运行时路径。

---

## 支持的输入/输出文件类型

| 类型 | 理由 |
|------|------|
| **CSV** | 数据处理最典型场景，Cangjie 手写解析可控 |
| **JSON** | 结构化数据，`encoding.json` 标准库可用 |
| **TXT** | 日志、自由文本，最简单 |
| **SQL** | 传 `.sql` 文件作为 query 或 schema dump |
| PDF | 暂缓：Cangjie 无成熟 PDF 解析库，demo 阶段性价比低 |

协议层对所有类型统一 base64 透传，文件类型感知在仓颉函数侧。

---

## Demo 包：stat_demo（新建独立包）

### 位置

```
/home/gloria/tianyue/
├── cliver/                    ← 主工程
├── cliver-tests/              ← 测试仓
└── stat_demo/                 ← 本次新建（与 cliver 并列）
```

### Public 函数列表

| 函数签名 | 返回 | 说明 |
|----------|------|------|
| `summarize(csvPath: String): String` | JSON | 每列 mean/median/std/min/max/count |
| `correlationMatrix(csvPath: String): String` | JSON | N×N Pearson 相关系数矩阵 |
| `linearRegression(csvPath: String, xCol: String, yCol: String): String` | JSON | slope/intercept/r_squared |
| `filterOutliers(csvPath: String, col: String, zThreshold: Float64): String` | 输出 CSV 路径 | z-score 过滤，结果写文件，agent download |
| `histogram(csvPath: String, col: String, bins: Int64): String` | JSON | bin 边界 + 计数数组 |

### 输入/输出模式

- `summarize` / `correlationMatrix` / `linearRegression` / `histogram`：直接返回 JSON string（stdout），agent 读 stdout
- `filterOutliers`：写出新 CSV 到 `/tmp/cliver/outputs/`，返回路径，agent 再 `download`

### 技术依赖

- `std.math.*`：`sqrt`, `pow`（计算 std dev, Pearson, R²）
- `std.fs.*`：文件读写
- `std.convert.*`：`Float64.tryParse()`
- `std.collection.ArrayList`：动态数组

---

## Demo 阶段边界

| 项 | Demo 阶段 | 后续扩展 |
|----|-----------|----------|
| 仓颉包来源 | 固定 `stat_demo` 包 | 接受动态传入源文件 + 重新 build |
| 文件类型 | CSV 为主，TXT/JSON 辅助 | SQL, 更多格式 |
| JiuwenClaw 状态 | 待部署，本阶段先实现 stat_demo 包 | 部署后接入 WebSocket 协议 |
| PDF 支持 | 不做 | 视需求决定 |

---

## 下一步

1. [ ] 确认 stat_demo 函数范围（全部五个 or 先三个）
2. [ ] 实现 `stat_demo/` 仓颉包
3. [ ] 用 Cliver 生成 driver，构建，验证 WebSocket 接口
4. [ ] JiuwenClaw 部署后，接入 WebSocket 协议层
