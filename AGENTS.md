<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:
- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->

# ClipAll 本地验收规则

- 需要用户在真实 macOS App 中验收时，完成自动验证后必须运行 `Scripts/install-local-app.sh`，将当前构建安装到 `/Applications/ClipAll.app` 并启动；不得只提供 `.app`、ZIP 或 DMG 让用户手动安装。仅当用户明确要求“只打包”时例外。
- 如果缺少稳定的本地签名身份，必须先说明 `Scripts/setup-local-signing.sh` 会在登录钥匙串中持久创建并信任本地代码签名证书，并等待用户明确授权。未获得该授权时，可使用 `CLIPALL_ADHOC=1 Scripts/install-local-app.sh` 完成低风险测试安装，同时提示辅助功能权限可能重置。
- 需要用户手动验收的任务，在用户明确表示测试通过前，不得 commit、归档 Trellis 任务或声称任务已经完成。
