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
- 每次执行本地安装前，必须先检查是否存在稳定的 `ClipAll Local Development` 代码签名身份；不得因为赶进度而跳过检查。
- 本地安装和真实 App 验收默认禁止使用 ad-hoc 签名，因为重新签名会让 macOS 辅助功能权限失效。若缺少稳定身份，必须停止安装，说明 `Scripts/setup-local-signing.sh` 会在登录钥匙串中持久创建并信任本地代码签名证书，并等待用户明确授权后再运行。
- 稳定证书建立后，后续每次本地构建都必须解析并使用同一个 `ClipAll Local Development` 身份；主 App、内嵌 `ClipAllPluginRunner` 与 `/Applications/ClipAll.app` 的签名身份和 designated requirement 必须一致。安装前后都要用 `codesign` 核验；发现身份或 requirement 漂移时必须停止替换并报告，不得通过重新签名、换证书或 ad-hoc 回退绕过。
- 只有用户明确要求“临时使用 ad-hoc 安装”时，才允许执行 `CLIPALL_ADHOC=1 Scripts/install-local-app.sh`；执行前必须再次提示辅助功能权限可能重置。不得把一次“批准实施”视为 ad-hoc 安装授权。
- 需要用户手动验收的任务，在用户明确表示测试通过前，不得 commit、归档 Trellis 任务或声称任务已经完成。
