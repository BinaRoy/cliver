## 期望的Cliver

> Cliver 从 Cangjie package 的 public API 生成 CLI driver、WebSocket backend 和 in-process session API，不需要手写适配。

"Agent 可用"的含义是：生成的接口有足够的结构（类型化参数、`commandKind`、参数 `role`、文件交接），让程序可以在没有人介入的情况下调用它。

## Cliver做什么

Cliver 读取一个 Cangjie package，生成两件东西：

**1. CLI driver**（`cli_driver.cj`）——一个和目标 package 编译在一起的 Cangjie 源文件。它把每个 public function、constructor、instance method 都映射到一个命令名，处理参数解析和类型转换，用 in-memory object store 让构造出来的对象可以在命令之间引用（`ref:1`、`ref:2` 等），同时暴露 `runFromArgs(args, store, nextId)` 供程序内调用。

**2. WebSocket backend**（`cli_ws_server.js`）+ 浏览器 UI（`index.html`）——一个包裹编译后 CLI binary 的 Node.js 服务。处理 `{ line: "..." }` 命令消息、文件 upload/download、以及 `$HANDLE` 替换。

净结果：一个原本没有任何外部接口的 Cangjie package，现在同时拥有 CLI、WebSocket API、浏览器 UI，以及 in-process 库 API——全部从源码生成，不需要手写适配。

---

## Cliver 应该有的功能边界

- 给出（`help --json`，带结构化 schema）， 让agent发现命令
- 参数 dispatch 和类型转换
- In-memory session 状态（object store + ref handle）
- 文件交接：把上传文件路由给 package 命令，把输出文件路由出去
- 机器可读输出（stdout/stderr 分离，命令输出干净）

---

## 现在能做什么

截至 commit `43f59aa`，对应 scope 逐项：

**命令发现（`help --json`）：** ✓
`help --json` 返回完整 schema，每条命令带 `commandKind`（`"constructor"`、`"function"`、`"method"`）、每个参数带 `role`（`"path"`、`"ref"`、`"plain"`），method 还附带 `className`。Agent 读这个 schema 可以知道哪些命令创建对象、哪些接受文件路径、哪些操作已有 ref。

**参数 dispatch 和类型转换：** ✓
生成 driver 在运行时把字符串参数转换为目标类型（`String`→`Int64`/`Float64`/`Bool`），把 `ref:N` 解析为 object store 里的对象，按 manifest 顺序做 overload 匹配。类型不匹配或 ref 不存在时返回非零 exit code 并写 stderr。

**In-memory session 状态（object store + ref handle）：** ✓
`runFromArgs(args, store, nextId)` 让调用方持有 session。同一个 `store` 传过多次调用，构造出来的对象持续存在，`nextId` 单调递增。

```
runFromArgs(["Student", "new", "Alice", "1001"], store, 1)    → ref:1，nextId=2
runFromArgs(["Student", "getName", "ref:1"], store, 2)        → stdout: "Alice"
runFromArgs(["Student", "setName", "ref:1", "Bob"], store, 3) → exitCode 0
runFromArgs(["Student", "getName", "ref:1"], store, 4)        → stdout: "Bob"
```

**文件交接：** ✓
Upload → `/tmp/cliver/uploads/`，backend 把 `$HANDLE` 替换为实际路径后派发命令；package 把输出写到 `/tmp/cliver/outputs/`，download 按路径取回。CLI 和 WebSocket 两条路径通过共享的 `_runLine()` 保持一致语义。由 `test_backend.js` 和 `scripts/run_adapter_demo.sh` 端到端验证。

**机器可读输出：** ✓
命令 stdout 和 stderr 分离（通过 `<<<CLIVE_STDERR>>>` 分隔符），`session finished` 等 session meta 只写 stderr，stdout 只包含命令结果。

---

## 当前实现与理想 Cliver 之间的 Gap

**Schema 没有 `returnRole`**

Schema 有 `returnType`（比如 `"String"`），但 agent 无法判断这个 String 是可下载的 artifact path，还是普通文本消息。`buildUploadReport` 返回的是文件路径，但 schema 里没有任何区分，agent 只能猜是否要尝试 download。

实现方式和现有 `role` 推断类似：对 `returnType == "String"` 且函数名含 report / path / output 等关键词的情况，在 schema 里加 `returnRole: "artifact"`。


**`runFromArgs` 不支持整行语义**

`runFromArgs(args, store, nextId)` 把参数数组直接包成单个 segment 执行，不经过 `_runLine`。In-process 调用者无法使用 `;` 分隔多命令、`NAME=cmd` 赋值、`$NAME` 替换——这些只在 WebSocket 路径上可用。

当前没有阻塞任何实际用例，只是 API 设计不整洁。修复方式是在 codegen 里暴露一个 `public func runLine(line: String, store, nextId): RunFromArgsResult`，约 10-20 行改动。这个 gap 和 P0 放在同一个 feature 里处理最合适，不属于 upload/download feature 的范围。

**Parser 静默跳过无法解析的函数**

Generic function 和复杂多行签名被静默跳过，schema 里不报告缺失。Agent 可能看不到一部分命令，而且不知道它们不见了。对当前 sample package 没有影响，对真实 package 是个隐患。

**没有函数描述**

Parser 不提取注释或 docstring。Agent 只能看签名，不知道函数实际做什么。当前 `commandKind`、`role` 和参数名已经提供了足够的结构信息，等 Cliver 用在真实业务 package 上时再处理。
