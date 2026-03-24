---
feature: agent-adapter-demo
status: Verified ✓
---

# Agent Adapter Demo — Implementation Notes

## Status

Verified — 4步流程全通过，exit 0。脚本已迁移至 `cliver-tests/demo/agent-adapter.js`。

## Implementation Notes

### stdout 解析修正
`help --json` 和命令执行的 stdout 末尾附带 `lesson_demo session finished\n`（CLI driver 的会话结束消息）。
`JSON.parse(stdout)` 直接失败。修正：
- `help --json`：用 `split('\n').find(l => l.trim().startsWith('{'))` 提取 JSON 行
- 命令输出路径：用 `split('\n').find(l => l.trim().length > 0)` 取第一个非空行

### 目录迁移
demo 脚本放在实现仓的 `demo/` 目录没有意义（它不是实现代码）。
验证通过后迁移至 `cliver-tests/demo/`，实现仓删除 `demo/` 目录。
`cliver-tests/` 中 `ws` 依赖已存在，无需额外安装。

## Known Gaps / Decisions

- **stdout 尾行问题**：已修复，见上。
- **无自动测试覆盖**：design.md 明确，人工验收为接受门槛。此为已知限制，非遗漏。
- **`runFromArgs()` 路径未覆盖**：design.md 明确 out of scope，WebSocket 路径覆盖更有价值。
