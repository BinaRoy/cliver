# Cliver 开发 Workflow

**适用项目：** Cliver（Cangjie package → CLI/backend 生成器）
**日期：** 2026-03-23

---

## 为什么 Cliver 的开发 workflow 和普通应用不同

Cliver 是代码生成器。它的输出（`cli_driver.cj`）需要和目标 package 一起编译才能运行。这意味着"测试通过"有两层含义：生成器本身正确，以及生成出来的代码在目标 package 里行为正确。两层都要覆盖。

---

## 开发流程

**1. 先写 design，明确要证明什么。**

写代码之前，先定义这个 feature 需要回答什么问题。例如 upload/download feature 的问题是："一个非人类调用方能否在没有人介入的情况下完整跑通 upload → execute → download？"其余所有决策都从这个问题推导出来。没有这个问题，很容易做出"能跑但没有证明任何事情"的实现。

**2. 做最小的实现来闭合证据链。**

不追求完整功能，只做能回答设计问题的最小代码。`buildUploadReport` 是 40 行故意写得很平淡的代码，它存在的唯一目的是给 upload→execute→download 链路提供一个真实的处理节点。功能越小，证据越干净。

**3. 把 sample package 当作集成测试 fixture。**

`sample_cangjie_package/src/cli_driver_test.cj` 中的测试同时覆盖生成器和生成出来的代码。在这里加测试，生成器和 driver 两侧都必须正确才能通过。这是唯一能同时约束两侧的测试位置。

**4. 用独立文件验证协议层。**

`test_backend.js` 只测 WebSocket server 行为——upload/download 机制、handle 替换、输出路径路由。这和生成的 Cangjie driver 的 dispatch 逻辑是完全不同的关注点，混在一起反而难以定位问题。

**5. 把 demo 自动化。**

`scripts/run_adapter_demo.sh` + `cliver-tests/demo/agent-adapter.js` 把人工运行 demo 的步骤变成可重复的回归检查。Demo 手册作为人工讲解的备用材料，不再是唯一的验证手段。

---

## 测试层次

```bash
cjpm test                                   # Cliver core：parser、codegen、dir 逻辑
cd sample_cangjie_package && cjpm test      # 生成的 driver + sample package 逻辑
node test_backend.js                        # WebSocket 协议 + 文件工作流
./scripts/run_adapter_demo.sh               # 完整 agent adapter 链路：discover→upload→execute→download
```

| 层次 | 捕捉什么 |
|------|---------|
| Cliver core 测试 | Parser/codegen 回归；生成了错误代码 |
| Sample package 测试 | 生成 driver 的 dispatch bug；session store 问题；JSON schema 错误 |
| Backend 测试 | Upload/download 协议断裂；路径路由；handle 替换 |
| Adapter demo | 端到端协议链；stdout 污染；JSON 解析失败 |

每一层独立运行，覆盖不同故障模式。某一层失败，就能直接定位问题属于哪个层。

---

## 真实案例：测试层次如何帮助定位问题

Adapter demo 层捕捉到过一个实际 bug：`session finished` 文本混入 stdout，导致 `JSON.parse(helpResp.stdout)` 失败。这个问题在 core 测试和 sample package 测试里都不可见——因为那两层不做 JSON 解析。只有端到端的 adapter demo 才能暴露它。

根因修复：把 `session finished` 从 `_out()` 改为 `_err()`，只写 stderr。这一行改动是因为有端到端测试存在才被发现和验证的。
