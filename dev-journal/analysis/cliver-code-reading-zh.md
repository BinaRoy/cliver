# Cliver 源码逐读与架构说明

## 1. 阅读目标

这份文档回答四个问题：

1. `cliver` 当前到底实现了哪些能力。
2. 这些能力分别映射到哪些源码文件、数据结构和执行链路。
3. 当你给 `cliver` 一个 Cangjie package 时，它从哪里进入、调到哪里、生成了什么、后续又怎么运行。
4. 当前实现的整体结构、边界与后续设计切入点是什么。

说明：

- 本文基于当前仓库源码阅读，不是基于 README 的二次转述。
- “逐行解释”这里采用“按连续代码段逐段逐行说明”的方式，而不是把每一行机械重述一遍。这样既保留细节，也更容易建立结构理解。
- 注释与解释全部使用中文。

---

## 2. 先给结论：Cliver 是什么

`cliver` 不是一个“直接执行目标 package”的运行时框架，而是一个“代码生成器”。

它的核心工作分成两步：

1. 读取目标 package 的源码，解析出可暴露为 CLI 的符号。
2. 根据这些符号生成一个新的 Cangjie 文件 `src/cli_driver.cj`，把 package API 包装成命令行接口。

也就是说：

- `cliver` 自己运行时，只做“扫描源码 + 生成文件 + 写文件”。
- 真正执行用户命令的，不是 `cliver` 本体，而是它生成出来的 `cli_driver.cj`。

这个区分非常重要，因为它直接决定了后续设计应分成：

- “分析器/生成器本体”怎么设计。
- “生成出来的 driver 运行时”怎么设计。

---

## 3. 仓库结构总览

### 3.1 顶层目录

```text
cliver/
├── src/
│   ├── main.cj
│   ├── parser.cj
│   ├── codegen.cj
│   ├── dir.cj
│   ├── dir_test.cj
│   ├── parser_test.cj
│   └── codegen_test.cj
├── sample_cangjie_package/
│   ├── src/
│   │   ├── main.cj
│   │   ├── cli_driver_test.cj
│   │   └── demo_sub/...
│   └── web/
├── docs/
├── scripts/
└── test/fixtures/
```

### 3.2 每个核心源码文件负责什么

| 文件 | 角色 | 它解决的问题 |
|---|---|---|
| `src/main.cj` | 主入口 | 读取 `--pkg` / `PKG_SRC`，调用解析器和生成器，写出 driver 与 web backend |
| `src/parser.cj` | 源码解析层 | 把目标 package 的源码转换成中间表示 `Manifest` |
| `src/codegen.cj` | 代码生成层 | 把 `Manifest` 拼成完整的 `cli_driver.cj` 源码字符串 |
| `src/dir.cj` | 路径语义层 | 统一处理递归扫描、子目录 packagePath、CLI 路径归一化 |
| `src/*_test.cj` | 单元测试 | 分别验证目录、解析、生成逻辑 |
| `sample_cangjie_package` | 集成样例 | 用来验证“真实 package 被 cliver 生成驱动后能否正常工作” |

---

## 4. 整体架构图

## 4.1 Cliver 本体架构

```text
用户执行 cliver
    │
    ▼
src/main.cj
    │
    ├── 解析输入路径（--pkg / PKG_SRC）
    ├── parsePackage(pkgPath)
    │       │
    │       ▼
    │   src/parser.cj
    │       │
    │       ├── src/dir.cj 收集 .cj 文件
    │       ├── std.ast 解析 AST
    │       └── 产出 Manifest
    │
    ├── generateDriver(manifest)
    │       │
    │       ▼
    │   src/codegen.cj
    │       │
    │       └── 产出完整 cli_driver.cj 字符串
    │
    ├── 写入 <pkg>/src/cli_driver.cj
    ├── 写入 <pkg>/web/cli_ws_server.js
    └── 尝试写入 <pkg>/web/index.html
```

## 4.2 生成后的运行架构

```text
用户在目标 package 中执行 cjpm run -- "<命令>"
    │
    ▼
生成出来的 src/cli_driver.cj
    │
    ├── 解析命令串
    ├── 识别 packagePath / command / built-ins
    ├── 做参数类型转换
    ├── 调目标 package 的 public API
    ├── 对 class 返回值存入对象仓库
    └── 输出结果或 ref:<id>
```

所以当前仓库其实有两个“运行时”：

- `cliver` 本体运行时：负责生成。
- 生成出的 CLI driver 运行时：负责执行目标 package 的命令。

---

## 5. 当你给出一个 package 时，cliver 实际怎么工作

假设你执行：

```bash
cjpm run -- --pkg /path/to/your/package
```

完整链路如下：

### 阶段 1：进入 `cliver` 自身入口

入口在 [src/main.cj](/home/gloria/tianyue/cliver/src/main.cj#L202)。

它做的事情：

1. 从命令行里查找 `--pkg <path>`。
2. 如果没有，再尝试环境变量 `PKG_SRC`。
3. 如果路径为空或还是当前目录 `"."`，直接报错退出。

### 阶段 2：解析目标 package

`main()` 调用 [parsePackage()](/home/gloria/tianyue/cliver/src/parser.cj#L271)。

`parsePackage()` 内部流程：

1. `_resolveSourceDir()` 判断传入的是 package 根目录还是源码目录。
2. `collectCjFilesUnder()` 递归扫描所有 `.cj` 文件。
3. `packagePathFromFile()` 为每个文件计算它在 CLI 里的逻辑目录，比如：
   - 根目录文件对应 `"/"`
   - `src/demo_sub/foo.cj` 对应 `"demo_sub"`
4. `readFileAsString()` 读取源码。
5. `cangjieLex()` + `parseProgram()` 把源码变成 AST。
6. `processProgram()` / `collectTopLevelDecl()` / `collectClassBodyDecl()` 提取：
   - `package` 名
   - `public func`
   - `public class` 的 `public init`
   - `public class` 的 public instance/static method
7. 产出 `Manifest`。

### 阶段 3：生成 CLI driver

`main()` 调用 [generateDriver()](/home/gloria/tianyue/cliver/src/codegen.cj#L19)。

`generateDriver()` 会把 `Manifest` 转成完整的 Cangjie 源码字符串，内容包含：

- `main()`
- `_runSegments()`
- `_printHelp()`
- `_printHelpJson()`
- `_storeRef()` / `_getRef()`
- 路径辅助函数
- 每个命令对应的 `_runXxx()`
- `runFromArgs()` 库入口
- `--serve-stdin` 模式

### 阶段 4：把生成结果写回目标 package

回到 [src/main.cj](/home/gloria/tianyue/cliver/src/main.cj#L236)：

1. 写 `<pkg>/src/cli_driver.cj`
2. 写 `<pkg>/web/cli_ws_server.js`
3. 尝试写 `<pkg>/web/index.html`

### 阶段 5：用户在目标 package 中运行生成后的 driver

进入目标 package 后，执行：

```bash
cjpm build
cjpm run -- "Student new Alice 1001"
```

此时运行的已经不是 `cliver` 本体，而是目标 package 里的 `cli_driver.cj` 所生成出来的程序。

---

## 6. 当前实现的核心中间结构：Manifest

`Manifest` 是整个项目里最关键的中间层。

定义见 [src/parser.cj](/home/gloria/tianyue/cliver/src/parser.cj#L23)。

### 6.1 `Manifest`

| 字段 | 含义 |
|---|---|
| `packageQualifiedName` | 目标 package 的包名 |
| `commands` | 所有可暴露命令的列表 |

### 6.2 `CommandInfo`

定义见 [src/parser.cj](/home/gloria/tianyue/cliver/src/parser.cj#L34)。

| 字段 | 含义 |
|---|---|
| `name` | 命令名；构造器固定为 `"init"`，普通函数为函数名 |
| `isConstructor` | 是否构造器 |
| `className` | 类名；构造器和方法命令使用 |
| `params` | 参数列表 |
| `returnType` | 返回类型字符串 |
| `returnIsRef` | 返回值是否被视为引用对象，需要进对象仓库 |
| `isInstanceMethod` | 是否实例方法 |
| `isStaticMethod` | 是否静态方法 |
| `packagePath` | 命令所属逻辑目录，如 `"/"`、`demo_sub` |

### 6.3 `ParamInfo`

定义见 [src/parser.cj](/home/gloria/tianyue/cliver/src/parser.cj#L58)。

| 字段 | 含义 |
|---|---|
| `paramName` | 参数名 |
| `paramType` | 参数类型字符串 |

### 6.4 为什么说 `Manifest` 是架构中心

因为：

- `parser.cj` 的输出是它。
- `codegen.cj` 的输入是它。
- 你后面如果要扩展功能，比如 flags、元信息、实例方法权限、命名空间策略，也大概率会先扩 `Manifest`。

---

## 7. 逐文件详细解读

## 7.1 `src/main.cj`：主入口与文件落盘

文件位置：[src/main.cj](/home/gloria/tianyue/cliver/src/main.cj)

### 7.1.1 文件头和依赖

参考 [src/main.cj:1](/home/gloria/tianyue/cliver/src/main.cj#L1) 到 [src/main.cj:8](/home/gloria/tianyue/cliver/src/main.cj#L8)。

- `package pkgcli` 说明 `cliver` 自己所在的包名是 `pkgcli`。
- `std.env.*` 用来读命令行和环境变量。
- `std.fs.*` 用来读写文件。

### 7.1.2 `_loadBackendScript()`：优先从资源文件加载 Web 后端脚本

参考 [src/main.cj:10](/home/gloria/tianyue/cliver/src/main.cj#L10) 到 [src/main.cj:26](/home/gloria/tianyue/cliver/src/main.cj#L26)。

这段逻辑做三层回退：

1. 如果设置了 `CLIVE_REPO_ROOT`，优先读 `<repo>/resources/cli_ws_server.js`
2. 否则尝试读当前目录下的 `resources/cli_ws_server.js`
3. 如果都失败，就退回到内嵌的 `_backendScriptTemplate()`

设计含义：

- 说明 Web backend 并不是编译时打包进资源系统，而是运行时尽量从文件取。
- 内嵌模板是最后保底，防止仓库外运行时找不到资源。

### 7.1.3 `_backendScriptTemplate()`：内嵌 Node.js backend 模板

参考 [src/main.cj:28](/home/gloria/tianyue/cliver/src/main.cj#L28) 到 [src/main.cj:199](/home/gloria/tianyue/cliver/src/main.cj#L199)。

这一大段虽然写在 `main.cj` 里，但本质上是在拼一个 JavaScript 文件模板。它做了这些事情：

- 起一个 HTTP + WebSocket 服务器。
- 服务 `index.html`。
- 接收浏览器发来的消息。
- 支持 upload/download。
- 把用户命令转成对子进程的调用。
- 默认调用目标 package 的二进制，或者退回 `cjpm run -- "<line>"`。
- 识别 `<<<CLIVE_STDERR>>>` 分隔符，把 stdout/stderr 分开回传给前端。

这说明一个架构事实：

- 当前 Web 终端不是一个独立产品，而是和 driver 生成一起交付的“附带运行层”。

### 7.1.4 `main()`：真正的 cliver 入口

参考 [src/main.cj:202](/home/gloria/tianyue/cliver/src/main.cj#L202) 到 [src/main.cj:267](/home/gloria/tianyue/cliver/src/main.cj#L267)。

可以把它分成 6 个连续步骤：

#### 第一步：提取目标 package 路径

对应 [src/main.cj:203](/home/gloria/tianyue/cliver/src/main.cj#L203) 到 [src/main.cj:218](/home/gloria/tianyue/cliver/src/main.cj#L218)。

- 先遍历命令行找 `--pkg`
- 没找到就查 `PKG_SRC`

这里没有复杂参数系统，说明当前工具入口非常薄。

#### 第二步：防止误写当前目录

对应 [src/main.cj:219](/home/gloria/tianyue/cliver/src/main.cj#L219) 到 [src/main.cj:222](/home/gloria/tianyue/cliver/src/main.cj#L222)。

如果路径还是 `"."` 或空字符串，就报错退出。

这其实是在防止把 driver 写进 `cliver` 自己仓库当前目录。

#### 第三步：调用解析器

对应 [src/main.cj:224](/home/gloria/tianyue/cliver/src/main.cj#L224) 到 [src/main.cj:229](/home/gloria/tianyue/cliver/src/main.cj#L229)。

- 调 `parsePackage(pkgPath)`
- 如果失败，退出码 `65`

#### 第四步：防止生成到 cliver 自己包里

对应 [src/main.cj:231](/home/gloria/tianyue/cliver/src/main.cj#L231) 到 [src/main.cj:234](/home/gloria/tianyue/cliver/src/main.cj#L234)。

如果解析出的包名是 `pkgcli`，就拒绝生成。

原因很直接：

- `cliver` 自己已经有一个 `main()`
- 再生成一个 `cli_driver.cj` 进去会产生第二个 `main()`

#### 第五步：调用生成器并写 driver

对应 [src/main.cj:236](/home/gloria/tianyue/cliver/src/main.cj#L236) 到 [src/main.cj:246](/home/gloria/tianyue/cliver/src/main.cj#L246)。

- `generateDriver(manifest)` 生成字符串
- 写到 `<pkg>/src/cli_driver.cj`

#### 第六步：写 web 资源

对应 [src/main.cj:247](/home/gloria/tianyue/cliver/src/main.cj#L247) 到 [src/main.cj:267](/home/gloria/tianyue/cliver/src/main.cj#L267)。

- 写 `web/cli_ws_server.js`
- 尝试写 `web/index.html`

这里有个很重要的现实约束：

- `cli_driver.cj` 是核心产物
- `web/cli_ws_server.js` 是可选增强
- `index.html` 则更像“样例前端复制”

所以后续设计上最好把这三类输出拆开看，不要混成同一抽象层。

---

## 7.2 `src/dir.cj`：路径和目录语义的单一事实来源

文件位置：[src/dir.cj](/home/gloria/tianyue/cliver/src/dir.cj)

这个文件非常小，但它在架构上的地位很高，因为 parser 和 driver 都依赖同一套路径语义。

### 7.2.1 根路径常量

参考 [src/dir.cj:16](/home/gloria/tianyue/cliver/src/dir.cj#L16) 到 [src/dir.cj:20](/home/gloria/tianyue/cliver/src/dir.cj#L20)。

- `rootPackagePath = "/"` 定义 CLI 目录系统的根。
- `_CHAR_SLASH = 47` 只是为了按字符码处理 `/`。

### 7.2.2 `collectCjFilesUnder()`：递归搜集 `.cj`

参考 [src/dir.cj:22](/home/gloria/tianyue/cliver/src/dir.cj#L22) 到 [src/dir.cj:57](/home/gloria/tianyue/cliver/src/dir.cj#L57)。

行为要点：

- 递归扫描目录
- 只收集 `.cj`
- 排除生成文件 `cli_driver.cj`

排除 `cli_driver.cj` 很关键，否则生成一次之后再跑解析器，会把生成产物再次当成用户源码读进去。

### 7.2.3 `_sortPathsByString()`：稳定排序

参考 [src/dir.cj:59](/home/gloria/tianyue/cliver/src/dir.cj#L59) 到 [src/dir.cj:74](/home/gloria/tianyue/cliver/src/dir.cj#L74)。

它用的是插入排序，目的是让文件遍历顺序稳定。

稳定顺序的重要性：

- 影响 package 名取“第一个 root 文件”的行为
- 影响 overload 收集顺序
- 影响最终生成代码的确定性

### 7.2.4 `packagePathFromFile()`：从物理路径映射到 CLI 逻辑目录

参考 [src/dir.cj:85](/home/gloria/tianyue/cliver/src/dir.cj#L85) 到 [src/dir.cj:99](/home/gloria/tianyue/cliver/src/dir.cj#L99)。

例子：

| 文件路径 | packagePath |
|---|---|
| `src/main.cj` | `"/"` |
| `src/demo_sub/demo_sub.cj` | `demo_sub` |
| `src/demo_sub/nested/nested.cj` | `demo_sub/nested` |

这就是为什么用户可以输入：

```bash
cjpm run -- "demo_sub/demo"
```

因为 `cliver` 不是只看函数名，还看函数所属目录。

### 7.2.5 `normalizePath()`：CLI 内部的路径解析

参考 [src/dir.cj:101](/home/gloria/tianyue/cliver/src/dir.cj#L101) 到 [src/dir.cj:175](/home/gloria/tianyue/cliver/src/dir.cj#L175)。

它实现了一个简化版 shell 路径系统：

- 支持绝对路径 `/`
- 支持相对路径
- 支持 `.`
- 支持 `..`
- 不允许越过根目录

这套逻辑后来会在 `codegen.cj` 里内联生成到 driver 中。

### 7.2.6 `isKnownPackagePath()`：校验可进入目录

参考 [src/dir.cj:206](/home/gloria/tianyue/cliver/src/dir.cj#L206) 到 [src/dir.cj:217](/home/gloria/tianyue/cliver/src/dir.cj#L217)。

它的语义不是“必须是叶子目录”，而是：

- 只要是已知目录本身，或者是某个已知目录的前缀目录，也算合法。

这样 `cd demo_sub` 才能成立，即便具体命令可能在 `demo_sub/nested`。

---

## 7.3 `src/parser.cj`：把源码提炼成 Manifest

文件位置：[src/parser.cj](/home/gloria/tianyue/cliver/src/parser.cj)

### 7.3.1 数据结构定义

参考：

- [src/parser.cj:12](/home/gloria/tianyue/cliver/src/parser.cj#L12)
- [src/parser.cj:23](/home/gloria/tianyue/cliver/src/parser.cj#L23)
- [src/parser.cj:34](/home/gloria/tianyue/cliver/src/parser.cj#L34)
- [src/parser.cj:58](/home/gloria/tianyue/cliver/src/parser.cj#L58)

这一段定义了解析层和生成层之间共享的协议。

这里尤其值得注意的是：当前 `CommandInfo` 已经支持

- 构造器
- 顶层函数
- 实例方法
- 静态方法

这比 README 中“只支持顶层函数和构造器”的描述更前进一步，说明实现已经扩展了。

### 7.3.2 `isRefType()`：引用类型判定是启发式的

参考 [src/parser.cj:68](/home/gloria/tianyue/cliver/src/parser.cj#L68) 到 [src/parser.cj:77](/home/gloria/tianyue/cliver/src/parser.cj#L77)。

规则很简单：

- 如果是 `Unit / Int / Float / Bool / String`，不是 ref
- 如果是 `Option<...>`，也不是 ref
- 其他一律当 ref

含义：

- 当前实现没有真正做类型系统级别判断
- 而是“字符串启发式判断”

这是未来设计里非常值得升级的一点。

### 7.3.3 `isPublic()` / `isStatic()`

参考：

- [src/parser.cj:79](/home/gloria/tianyue/cliver/src/parser.cj#L79)
- [src/parser.cj:92](/home/gloria/tianyue/cliver/src/parser.cj#L92)

这两个函数都直接遍历 `Decl.modifiers`。

这是很干净的 AST 层写法，没有走字符串匹配。

### 7.3.4 `isOperatorMethodName()`：过滤操作符方法

参考 [src/parser.cj:105](/home/gloria/tianyue/cliver/src/parser.cj#L105) 到 [src/parser.cj:119](/home/gloria/tianyue/cliver/src/parser.cj#L119)。

它通过首字符是否是字母或 `_` 来判断一个方法名是不是普通标识符。

目的：

- 像 `operator ==` 这种方法，不暴露成 CLI 命令。

### 7.3.5 `isGenericFuncDecl()`：过滤泛型函数

参考 [src/parser.cj:121](/home/gloria/tianyue/cliver/src/parser.cj#L121) 到 [src/parser.cj:142](/home/gloria/tianyue/cliver/src/parser.cj#L142)。

这里没有直接问 AST “你是不是泛型函数”，而是：

1. 拿 token 序列
2. 找到 `FUNC`
3. 找到函数名
4. 看后面跟的是 `<` 还是 `(`

这说明当前 Cangjie AST API 可能不足以直接给出一个稳定的泛型标志，所以作者采用了 token 级旁路判断。

### 7.3.6 `getReturnTypeStr()` / `getParamList()`

参考：

- [src/parser.cj:153](/home/gloria/tianyue/cliver/src/parser.cj#L153)
- [src/parser.cj:162](/home/gloria/tianyue/cliver/src/parser.cj#L162)

作用很直接：

- 从 `FuncDecl` 抽出返回类型
- 从 `funcParams` 抽出参数列表

这两段是 `CommandInfo` 的构建基础。

### 7.3.7 `collectClassBodyDecl()`：类成员命令提取的核心

参考 [src/parser.cj:176](/home/gloria/tianyue/cliver/src/parser.cj#L176) 到 [src/parser.cj:201](/home/gloria/tianyue/cliver/src/parser.cj#L201)。

这段非常关键，它决定了类里的东西如何变成 CLI 命令：

- `public init(...)`
  - 转成构造器命令
  - `name = "init"`
  - `className = 类名`
  - `returnType = 类名`
  - `returnIsRef = true`

- `public static func`
  - 转成静态方法命令
  - 参数保持原样

- `public func`
  - 转成实例方法命令
  - 会在参数列表最前面人为插入一个 `this: ClassName`

也就是说，实例方法在 CLI 层的真实参数形式其实是：

```text
ClassName method ref:<this> otherArg1 otherArg2
```

这就是“对象仓库 + ref”机制和实例方法支持能接起来的原因。

### 7.3.8 `processProgram()` 和 `collectTopLevelDecl()`

参考：

- [src/parser.cj:212](/home/gloria/tianyue/cliver/src/parser.cj#L212)
- [src/parser.cj:227](/home/gloria/tianyue/cliver/src/parser.cj#L227)

`processProgram()` 做两件事：

1. 从 root 层第一个有 package 声明的文件提取包名
2. 遍历顶层声明并交给 `collectTopLevelDecl()`

`collectTopLevelDecl()` 做三类事情：

- 发现 public class，就深入收集构造器和方法
- 发现 public func，就收集为顶层函数命令
- 其他声明忽略

### 7.3.9 `_resolveSourceDir()`：允许传 package 根，也允许传 src 目录

参考 [src/parser.cj:255](/home/gloria/tianyue/cliver/src/parser.cj#L255) 到 [src/parser.cj:268](/home/gloria/tianyue/cliver/src/parser.cj#L268)。

如果目录下存在 `src/`，就扫描 `src/`；否则直接扫描传入目录。

这使得用户既可以传：

- package 根目录
- 直接传源码目录

### 7.3.10 `parsePackage()`：解析主流程

参考 [src/parser.cj:271](/home/gloria/tianyue/cliver/src/parser.cj#L271) 到 [src/parser.cj:296](/home/gloria/tianyue/cliver/src/parser.cj#L296)。

完整执行顺序：

1. 解析 source dir
2. 收集 `.cj`
3. 依次读取文件
4. 词法分析
5. AST 解析
6. 提取命令
7. 最终返回 `Manifest`

这个函数的架构特征很清楚：

- 它是一个“批量扫描 + 累积状态”的 pipeline
- 失败策略是“遇到解析异常就整体失败”
- 没有文件级容错和错误聚合

---

## 7.4 `src/codegen.cj`：把 Manifest 展开成完整 driver

文件位置：[src/codegen.cj](/home/gloria/tianyue/cliver/src/codegen.cj)

这是整个项目里最复杂、最核心的文件。

从职责上看，它不是一个“简单模板填充器”，而是一个“把 Manifest 扩展成运行时系统”的代码生成器。

### 7.4.1 `generateDriver()` 入口

参考 [src/codegen.cj:17](/home/gloria/tianyue/cliver/src/codegen.cj#L17) 到 [src/codegen.cj:668](/home/gloria/tianyue/cliver/src/codegen.cj#L668)。

这一个函数承担了几乎所有 driver 结构拼装工作。

可以把它拆成以下子阶段。

### 7.4.2 生成头部、包名、import

参考 [src/codegen.cj:23](/home/gloria/tianyue/cliver/src/codegen.cj#L23) 到 [src/codegen.cj:63](/home/gloria/tianyue/cliver/src/codegen.cj#L63)。

主要做：

- 写注释头
- 写 `package xxx`
- 写标准库 import
- 给子包补 import
- 对子包符号生成 alias import

这里暴露出一个很重要的设计点：

- 生成的 driver 与目标 package 位于同一个 module
- 但对子 package 中的类型和函数，仍然要做作用域引入

### 7.4.3 生成会话状态、输出缓冲、对象仓库

参考 [src/codegen.cj:65](/home/gloria/tianyue/cliver/src/codegen.cj#L65) 到 [src/codegen.cj:136](/home/gloria/tianyue/cliver/src/codegen.cj#L136)。

这里生成了：

- `_SessionState`
- `_sessionState`
- `_outBuf` / `_errBuf`
- `_out()` / `_err()`
- `_nextId`
- `_store`
- `_storeRef()`
- 可选 `_getRef()` / `_parseRefId()`

这表示 driver 运行时内建了三种状态：

1. 对象引用状态
2. 当前工作目录状态 `_cwd`
3. 输出捕获状态

这已经不是“纯函数式命令调度器”，而是一个有 session 概念的命令运行时。

### 7.4.4 把 Manifest 重组为命令分发表

参考 [src/codegen.cj:187](/home/gloria/tianyue/cliver/src/codegen.cj#L187) 到 [src/codegen.cj:243](/home/gloria/tianyue/cliver/src/codegen.cj#L243)。

这段代码会先把 `manifest.commands` 分组：

- 普通命令按 `(packagePath, key)` 分组
- 类方法按 `(packagePath, className, methodName)` 分组

原因：

- 后面要为每组命令生成一个 `_runXxx()`
- 一组里可能有多个 overload

### 7.4.5 生成 `_runSegments()`：driver 的主调度器

参考 [src/codegen.cj:245](/home/gloria/tianyue/cliver/src/codegen.cj#L245) 到 [src/codegen.cj:359](/home/gloria/tianyue/cliver/src/codegen.cj#L359)。

这是生成出来的 driver 的核心调度循环。

它做的事情：

1. 遍历每个 segment
2. 取第一个 token 当命令名
3. 如果 token 里含 `/`，拆成 `dirPart + commandPart`
4. 先处理 built-in：
   - `cd`
   - `help`
   - `dir`
   - `echo`
5. 再匹配实例/静态方法命令
6. 再匹配普通函数和构造器命令
7. 都匹配不到则报 `Unknown command`

这段代码告诉我们：当前 driver 的命令模型不是 flat command list，而是：

```text
(当前目录或显式目录) + 命令名 + 参数
```

### 7.4.6 生成命令行分段与 session 处理

参考 [src/codegen.cj:361](/home/gloria/tianyue/cliver/src/codegen.cj#L361) 到 [src/codegen.cj:572](/home/gloria/tianyue/cliver/src/codegen.cj#L572)。

这里生成的是 driver 的“命令行运行时壳层”：

- `_normalizeCommandLine()`
- `_tokenizeStdinLine()`
- `_findLastRefInStdout()`
- `_serveStdin()`
- 生成出来的 `main()`
- `runFromArgs()`

其中最重要的是三种执行入口：

| 入口 | 用途 |
|---|---|
| `main()` | 普通 CLI 运行 |
| `_serveStdin()` | 长会话 stdin 模式 |
| `runFromArgs()` | 作为库函数给 actor / web session 调用 |

这说明当前 driver 实际已经支持三种消费方式：

1. 命令行进程式调用
2. 会话式 stdin 调用
3. 嵌入式库调用

### 7.4.7 帮助信息生成

参考 [src/codegen.cj:574](/home/gloria/tianyue/cliver/src/codegen.cj#L574) 到 [src/codegen.cj:644](/home/gloria/tianyue/cliver/src/codegen.cj#L644)。

这里生成：

- `_printHelp()`
- `_printHelpJson()`

`help --json` 特别值得注意，因为它意味着：

- driver 不只是面向人
- 它也开始面向 agent / UI / 自动化发现

这可能是后续设计一个很好的扩展点，例如把 schema 输出做成正式 API。

### 7.4.8 `_emitPathHelpers()`：把路径系统复制进生成代码

参考 [src/codegen.cj:732](/home/gloria/tianyue/cliver/src/codegen.cj#L732) 到 [src/codegen.cj:824](/home/gloria/tianyue/cliver/src/codegen.cj#L824)。

这里把 `dir.cj` 中的路径逻辑“内联复制”到生成代码里。

优点：

- 生成产物是自包含的

代价：

- 路径逻辑在 `dir.cj` 和生成出来的 driver 中各有一份
- 未来修改路径语义时，要注意两边保持一致

### 7.4.9 子包 import / alias 体系

参考：

- [src/codegen.cj:869](/home/gloria/tianyue/cliver/src/codegen.cj#L869)
- [src/codegen.cj:925](/home/gloria/tianyue/cliver/src/codegen.cj#L925)
- [src/codegen.cj:1068](/home/gloria/tianyue/cliver/src/codegen.cj#L1068)
- [src/codegen.cj:1075](/home/gloria/tianyue/cliver/src/codegen.cj#L1075)

这一组函数说明生成器花了不少精力在解决“子 package 类型/函数如何在 driver 中被正确引用”这个问题。

核心策略：

- 给子包符号生成 deterministic alias
- 避免直接写全限定名
- 对类型和函数分别做路径处理

这部分其实是当前实现中最容易继续抽象化的一层，因为它隐含了一个“名称解析系统”。

### 7.4.10 `_emitRunCommand()`：为每个命令组生成一个执行函数

参考 [src/codegen.cj:1100](/home/gloria/tianyue/cliver/src/codegen.cj#L1100) 到 [src/codegen.cj:1138](/home/gloria/tianyue/cliver/src/codegen.cj#L1138)。

生成模式如下：

- 每个命令 key 生成一个 `_runXxx(args)`
- 构造器先检查 `new`
- 依次尝试 overload
- 都不匹配则报错

这里实现的是：

- overload 决策层
- 不是 dispatcher 本身

dispatcher 在 `_runSegments()`，而 `_runXxx()` 是每个命令组自己的“本地匹配器”。

### 7.4.11 `_emitConvert()`：参数转换核心

参考 [src/codegen.cj:1171](/home/gloria/tianyue/cliver/src/codegen.cj#L1171) 到 [src/codegen.cj:1242](/home/gloria/tianyue/cliver/src/codegen.cj#L1242)。

它针对不同类型生成不同转换代码：

| 类型 | 转换策略 |
|---|---|
| `Int64` | `Int64.tryParse` |
| `Float64` | `Float64.tryParse` |
| `Bool` | `Bool.tryParse` |
| `String` | 直接包成 `Option<String>.Some` |
| `Option<T>` | 针对基础类型特殊展开 |
| 其他类型 | 按对象引用 `ref:<id>` 查仓库并 cast |

这里要特别注意：

- 类类型参数不能直接从字面量构造
- 必须传 `ref:<id>`

这就决定了当前 driver 的交互模型是“先构造对象，再串联引用”。

### 7.4.12 `_emitCall()`：真正发起 API 调用

参考 [src/codegen.cj:1281](/home/gloria/tianyue/cliver/src/codegen.cj#L1281) 到 [src/codegen.cj:1366](/home/gloria/tianyue/cliver/src/codegen.cj#L1366)。

这里分四种调用路径：

1. 构造器调用：`ClassName(...)`
2. 实例方法调用：`(this).method(...)`
3. 静态方法调用：`ClassName.method(...)`
4. 顶层函数调用：`func(...)` 或 alias 调用

调用后再处理返回值：

- 如果 `returnIsRef = true`，存仓库并打印 `ref:<id>`
- 如果返回 `Unit`，直接结束
- 否则打印 `toString()`

所以“调用目标 package API”只是 `_emitCall()` 的一部分，后面还叠加了“CLI 结果协议”。

---

## 8. 示例 package 是怎么被接入的

示例代码位置：

- [sample_cangjie_package/src/main.cj](/home/gloria/tianyue/cliver/sample_cangjie_package/src/main.cj)
- [sample_cangjie_package/src/demo_sub/demo_sub.cj](/home/gloria/tianyue/cliver/sample_cangjie_package/src/demo_sub/demo_sub.cj)
- [sample_cangjie_package/src/demo_sub/nested/nested.cj](/home/gloria/tianyue/cliver/sample_cangjie_package/src/demo_sub/nested/nested.cj)

### 8.1 根 package 中有哪些可暴露能力

从 [sample_cangjie_package/src/main.cj](/home/gloria/tianyue/cliver/sample_cangjie_package/src/main.cj) 可以读出：

- `public class Student`
  - 构造器可暴露
  - 实例方法如 `getName`, `setName`, `getId`, `setId` 可暴露
- `public class Lesson`
  - 构造器可暴露
  - 实例方法如 `add`, `remove`, `printStudents`, `printStudentNames`, `getStudentCount` 可暴露
- 顶层函数：
  - `demo`
  - `addStudentToLesson`
  - `printLessonStudentNames`
  - `lessonStudentCount`

### 8.2 子 package 中的命令路径

`demo_sub/demo_sub.cj` 对应 `packagePath = demo_sub`

`demo_sub/nested/nested.cj` 对应 `packagePath = demo_sub/nested`

因此用户可以运行：

```bash
cjpm run -- "demo_sub/demo"
cjpm run -- "demo_sub/nested/demo"
```

### 8.3 一个真实命令的执行链示例

以：

```bash
cjpm run -- "Student new Alice 1001"
```

为例，生成后的 driver 运行链路是：

1. `main()` 收到整条命令
2. `_normalizeCommandLine()` 规范化
3. `_tokenizeStdinLine()` 切成 token
4. `_runSegments()` 识别命令 `Student`
5. 命中构造器组 `_runStudent(...)`
6. `_emitConvert()` 生成的代码把：
   - `"Alice"` -> `String`
   - `"1001"` -> `Int64`
7. `_emitCall()` 生成的代码调用 `Student("Alice", 1001)`
8. 因为返回类型是类对象，调用 `_storeRef(_result)`
9. 输出 `ref:1`

再比如：

```bash
cjpm run -- "addStudentToLesson ref:1 ref:2"
```

执行链就是：

1. `_runSegments()` 命中顶层函数 `addStudentToLesson`
2. 参数都按 ref 类型处理
3. `_getRef(1)` 取 `Student`
4. `_getRef(2)` 取 `Lesson`
5. 调 `addStudentToLesson(student, lesson)`

---

## 9. 测试结构说明

### 9.1 `src/dir_test.cj`

文件位置：[src/dir_test.cj](/home/gloria/tianyue/cliver/src/dir_test.cj)

覆盖点：

- 根路径归一化
- `..` 越界处理
- `packagePathFromFile()`
- known path 判定

### 9.2 `src/parser_test.cj`

文件位置：[src/parser_test.cj](/home/gloria/tianyue/cliver/src/parser_test.cj)

覆盖点：

- 最小 fixture 能否解析成功
- invalid path 是否正确失败

### 9.3 `src/codegen_test.cj`

文件位置：[src/codegen_test.cj](/home/gloria/tianyue/cliver/src/codegen_test.cj)

覆盖点：

- 生成结果是否包含 package / commands / ref 等关键结构

### 9.4 `sample_cangjie_package/src/cli_driver_test.cj`

文件位置：[sample_cangjie_package/src/cli_driver_test.cj](/home/gloria/tianyue/cliver/sample_cangjie_package/src/cli_driver_test.cj)

这是最重要的集成测试，验证的是“生成出来的东西能不能真跑”。

它覆盖了：

- 多命令串行时 `ref:1`、`ref:2`、`ref:3`
- `runFromArgs()`
- built-in 命令
- 子 package 命令
- 错误路径

这说明当前测试策略是：

- `src/` 内测纯逻辑
- `sample package` 内测真实生成物

---

## 10. 当前实现支持的功能清单

按能力归类如下。

### 10.1 解析侧

- 递归扫描 `.cj`
- 支持 package 根目录或直接源码目录
- 提取 root package 名
- 提取 public 顶层函数
- 提取 public 构造器
- 提取 public 实例方法
- 提取 public 静态方法
- 过滤 operator 方法
- 过滤泛型函数

### 10.2 生成侧

- 生成完整 `cli_driver.cj`
- 生成 WebSocket backend
- 尝试复制 `index.html`
- 支持子 package import / alias

### 10.3 运行时侧

- 普通 CLI 运行
- `;` 多段命令
- `NAME = command` / `$NAME` 环境变量式引用
- `ref:<id>` 对象仓库机制
- `cd` / `dir` / `help` / `echo`
- `help --json`
- `runFromArgs()`
- `--serve-stdin`

### 10.4 Web 侧

- WebSocket 交互
- 会话 idle timeout
- upload/download
- stdout / stderr 分离回传

---

## 11. 当前结构的优点与局限

### 11.1 优点

- 架构主线很清楚：`parse -> manifest -> generate`
- Manifest 是天然的扩展点
- driver 自包含，目标 package 易于集成
- sample package 测试链路比较完整
- 已经支持子 package 与对象引用，能力比“最小 CLI 包装器”更强

### 11.2 局限

#### 1. `codegen.cj` 过重

它同时承担：

- 代码模板拼接
- 运行时设计
- import 解析
- 路径系统
- 参数转换策略
- help schema 输出

后续如果功能继续增长，这里会是主要复杂度热点。

#### 2. 类型系统判断偏启发式

`isRefType()` 只是字符串判断，不是真正类型解析。

#### 3. parser 错误恢复能力弱

一个文件 parse 失败就整体失败，没有聚合错误信息。

#### 4. 生成器和生成物之间存在逻辑镜像

例如路径规则在 `dir.cj` 和生成代码里各自保存了一份。

#### 5. web 资源生成和 CLI driver 生成耦合较紧

这在产品形态继续分化时会变得不够灵活。

---

## 12. 如果后续要做设计，可以重点从哪里切

结合当前结构，我建议后续设计优先从以下几个方向切入。

### 12.1 把 `Manifest` 扩成正式 IR

比如增加：

- 命令来源类型
- 文档字符串
- 可见性策略
- 参数默认值
- 是否可流式输出
- 错误元信息

这是最稳的扩展路径。

### 12.2 把 `codegen.cj` 拆层

建议至少拆成：

- manifest 归并层
- import / name resolution 层
- runtime template 层
- command emitter 层

### 12.3 明确区分“生成器产物类型”

当前至少有三类产物：

- CLI driver
- web backend
- web frontend 资源

后续最好分别建模，而不是都塞在 `main.cj` 里顺手写文件。

### 12.4 把运行时协议显式化

例如把这些协议整理成正式设计对象：

- `ref:<id>`
- `NAME = command`
- `$NAME`
- `help --json`
- stdout/stderr delim

因为这些已经构成了一个小型交互协议，而不只是临时实现细节。

---

## 13. 一句话总结当前架构

当前 `cliver` 的本质是：

> 一个读取 Cangjie package 源码、抽取 public API、生成自包含 CLI driver 和 web 辅助运行层的代码生成工具；其中 `Manifest` 是核心中间层，`codegen.cj` 是当前复杂度中心，而真正执行目标 package 命令的是生成出来的 `cli_driver.cj`，不是 `cliver` 本体。

---

## 14. 这份文档最适合怎么继续用

如果你下一步要做后续设计，我建议直接基于这三层来写设计：

1. 解析层：`parser + dir + Manifest`
2. 生成层：`codegen`
3. 运行层：generated driver / web backend

这样设计讨论会更稳，不会把“源码解析器的问题”和“driver 运行时的问题”混在一起。

---

## 15. 按功能划分的后续开发计划

这一节的目标不是把 roadmap 拉得很大，而是回答一个更现实的问题：

> 从当前实现出发，`cliver` 在产品上应该扮演什么角色？为了做一个小而有力的 demo，它最少还缺什么？

我建议把 `cliver` 的角色定义为：

> `cliver` 不负责做 agent 本身，它负责把 Cangjie package 变成 agent 可发现、可调用、可组合使用的工具接口。

如果接受这个定位，那么后续开发就应该优先围绕“接入成本低、demo 可证明、保持简单”这三个目标展开。

### 15.1 角色定位：`cliver` 应该做什么，不应该做什么

`cliver` 应该做的事：

- 从 package 源码中发现可用能力。
- 生成统一的调用入口。
- 提供 agent 可以读取的命令清单和参数信息。
- 提供基本的会话、引用、文件输入输出支持。

`cliver` 不必承担的事：

- 不必实现完整 agent 框架。
- 不必自己做复杂的任务规划。
- 不必内建复杂 UI 或复杂 workflow engine。

这个边界很重要，因为它意味着后续开发不应把系统做成“大而全的平台”，而应做成“package 到 tool interface 的转换层”。

### 15.2 先以 demo 为导向：最小可证明路径

如果 manager 的问题是 “can we have a small demo?”，那么 demo 最应该证明的是：

1. `cliver` 暴露出的 command list 可以被 agent 自动发现。
2. agent 能利用这些 command 完成一个多步任务。
3. 新 feature `upload/download` 不只是 UI 功能，而是真的进入了工具调用链路。

从当前实现看，已经具备 demo 基础的部分有：

- `help --json` 可作为 command/schema discovery 的起点，见 [src/codegen.cj](/home/gloria/tianyue/cliver/src/codegen.cj#L608)。
- `runFromArgs()` 可作为 actor/backend 的库入口，见 [src/codegen.cj](/home/gloria/tianyue/cliver/src/codegen.cj#L552)。
- Web backend 已支持 upload/download，见 [src/main.cj](/home/gloria/tianyue/cliver/src/main.cj#L69) 和 [src/main.cj](/home/gloria/tianyue/cliver/src/main.cj#L88)。

但当前实现距离“一个能说服人的 demo”仍然缺少几块关键能力。

### 15.3 模块 A：Discovery 与 Tool Schema

当前已有：

- `help`
- `help --json`

当前缺失：

- `help --json` 的字段比较薄，只覆盖命令名、packagePath、返回类型、参数名和参数类型。
- 没有明确标出命令类别：顶层函数、构造器、实例方法、静态方法。
- 没有文档字段、示例字段、是否要求 `ref`、是否产生文件路径等语义信息。

在保持简单的前提下，建议优先补：

1. 扩展 `help --json` schema
   - 增加 `kind`
   - 增加 `description`
   - 增加 `inputMode`
   - 增加 `returnsRef`
2. 增加单命令帮助
   - 例如 `help Student`
   - 或 `help summarizeFile`

为什么这块优先级高：

- agent 接入首先依赖 discovery。
- 这类改动成本相对低，但对 demo 说服力很强。
- 它能直接回答 “agents like OpenClaw can hook up?” 这个问题。

### 15.4 模块 B：Session 与 Actor 接入

当前已有：

- `runFromArgs(args, store, nextId)` 作为库入口。
- `ref:<id>` 和对象仓库机制。

当前缺失：

- Node backend 仍然是 one process per message，跨消息没有持久 session。
- `runFromArgs()` 只吃单条 argv，不处理 `;`、`NAME = command`、`$NAME` 的整行语义。
- 文档里已经说明 actors backend 是“可选方向”，但仓库中没有一个真正的 actor demo backend。

在保持简单的前提下，建议优先补：

1. 做一个最小 actor demo backend
   - 不追求通用框架
   - 只证明一个 session actor 能持有 `store + nextId`
2. 补一个“line -> segments -> runFromArgs”的薄适配层
   - 把当前 `main()` 的整行处理逻辑抽成可复用函数
   - 让 actors backend 和 CLI backend 共用语义

为什么这块重要：

- 当前最大证据缺口不是“页面能不能用”，而是“agent backend 是否真正接得上”。
- 有了最小 actor demo，就能把 `cliver` 从“web CLI 工具”提升到“agent 工具接入层”。

### 15.5 模块 C：Upload / Download 与文件工作流

当前已有：

- 后端支持 upload
- 后端支持 download
- 路径限制在 `/tmp/cliver/` 下，安全边界相对清楚

当前缺失：

- `sample_cangjie_package` 主要演示对象引用和命令组合，不演示文件处理。
- 没有一个标准 demo package 展示“上传文件 -> package 处理 -> 产出文件 -> 下载”。
- `help --json` 里也没有标出某个命令是否适合接收 path / 生成 path。

在保持简单的前提下，建议优先补：

1. 新增一个最小文件处理 demo package
   - 输入：文件路径
   - 输出：结果文件路径
2. 在 demo package 中只暴露 2 到 3 个命令
   - `inspectFile(path: String)`
   - `summarizeFile(inputPath: String, outputPath: String)`
   - 或 `wordCountFile(inputPath: String, outputPath: String)`
3. 约定输出目录
   - 统一写 `/tmp/cliver/outputs/...`

为什么这块非常关键：

- manager 已经明确指出，他们要看的不是“人可以点 web page”，而是“agent 可以 hook up cj package 并且有用”。
- upload/download 只有在文件工作流里才真正体现价值。

### 15.6 模块 D：Parser / IR 的稳健性

当前已有：

- 基于 `std.ast` 的解析主线
- `Manifest` 作为中间结构

当前缺失：

- `Manifest` 还不是正式的 tool IR
- 错误聚合弱
- 类型判定偏启发式，尤其是 `isRefType()`
- 没有把源码位置信息保留下来

在保持简单的前提下，建议优先补：

1. 给 `Manifest` 增加少量面向工具调用的元信息
   - 命令描述
   - 参数描述
   - 命令类别
2. 给 parser 错误增加文件级上下文
   - 至少能告诉用户是哪个文件、哪类声明失败

为什么这块不是第一优先级：

- 它更偏中长期稳健性，而不是 demo 的第一阻塞项。
- 但一旦 demo 做成，这里会成为后续扩展的基础。

### 15.7 模块 E：生成器拆层与维护性

当前已有：

- 单文件 `codegen.cj` 完成全部生成

当前缺失：

- 名称解析、路径规则、运行时模板、命令发射混在一起
- 后续如果再补 schema、actor 支持、文件工作流，复杂度会继续集中在 `codegen.cj`

在保持简单的前提下，建议优先补：

1. 不必立刻大拆文件
2. 先做小规模结构化
   - schema emitter
   - runtime emitter
   - command emitter

这样做的原因是：

- 现在最重要的是降低后续迭代风险
- 不是为了追求“架构美观”

### 15.8 推荐的开发顺序

如果目标是 “先做一个小 demo，看还缺什么”，我建议按下面顺序推进。

#### Phase 1：把 demo 证据链补全

目标：

- 证明 agent 可发现命令
- 证明 agent 可完成一次多步任务
- 证明 upload/download 进入真实工作流

优先做：

1. 增强 `help --json`
2. 增加最小文件处理 demo package
3. 写一份 agent demo script

#### Phase 2：把 agent backend 证据补全

目标：

- 证明不只是 web UI，而是真的能由 agent backend 长期接入

优先做：

1. 最小 actor demo backend
2. 把整行语义从 `main()` 中抽出，供 `runFromArgs()` 复用

#### Phase 3：补稳健性

目标：

- 支撑后续更多 package 和更复杂的 API

优先做：

1. 扩 `Manifest`
2. 改进 parser 错误
3. 拆分 `codegen.cj`

### 15.9 一个“保持简单”的版本里，cliver 还应该提供哪些功能

如果坚持简单，我认为只需要再补以下几类能力，就足以把 `cliver` 从“有趣工具”推进到“可演示、可讨论、可继续投资源”的状态：

1. 更好的 schema discovery
   - 让 agent 少猜
2. 一个文件工作流 demo
   - 让 upload/download 真正有意义
3. 一个最小 actor/backend demo
   - 让 “hook up to agents” 有直接证据
4. 少量命令级描述信息
   - 让 demo 更自然，也让 manager 更容易理解

不建议短期内优先做的事：

- 复杂权限系统
- 很重的配置 DSL
- 多 package 聚合平台
- 复杂图形化编排器

这些都可能把 `cliver` 从“简单的接入层”拉成“复杂的平台”，不符合当前阶段。

### 15.10 一句话版计划总结

如果要用最小代价回答 manager 的问题，我建议后续计划收敛成一句话：

> 先把 `cliver` 明确做成 “Cangjie package 到 agent tool interface 的转换层”，然后围绕一个小而完整的 demo，优先补齐 schema discovery、文件工作流和最小 actor 接入证据；等 demo 跑通后，再决定 parser 和 codegen 的更深层扩展是否值得投入。
