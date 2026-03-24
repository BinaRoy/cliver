# Dev Journal

Agent 入口：**[AGENT.md](AGENT.md)**

## 目录

```
AGENT.md                            ← 每次开发的起点（状态 + 导航 + 清单）
process/
└── feature-workflow.md             ← feature 开发流程（phase 0-3）
features/
└── YYYY-MM-DD-<name>/
    ├── design.md                   ← 决策、边界、协议（开始前写）
    ├── impl.md                     ← 实现笔记、状态（过程中更新）
    └── tracker.md                  ← 执行追踪、checkpoint、测试数字、task 进度
```

## Feature 索引

| Date | Feature | Status |
|------|---------|--------|
| 2026-03-17 | [upload-download](features/2026-03-17-upload-download/) | Verified ✓ |
| 2026-03-19 | [agent-integration](features/2026-03-19-agent-integration/) | Verified ✓ (Feature A+B only; Feature C → agent-adapter-demo) |
| 2026-03-23 | [agent-adapter-demo](features/2026-03-23-agent-adapter-demo/) | Verified ✓ |
| 2026-03-23 | [agent-backend-hardening](features/2026-03-23-agent-backend-hardening/) | Design draft (Phase 0 in progress) |
