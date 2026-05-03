# codex-check

A wrapper plugin for [Claude Code](https://claude.com/claude-code) that adds auto-trigger boundaries, output triage, and per-project setup on top of [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc).

The official OpenAI plugin gives Claude Code users `/codex:review` and `/codex:adversarial-review` — codex-check adds the orchestration above those primitives so Claude knows *when* to invoke them on its own work, and how to triage what comes back.

## Status

Design phase. The full design lives at [docs/design.md](docs/design.md). Implementation in progress.

## What it will do (v1)

- **Auto-trigger** Codex review when Claude finishes complex debugging or touches high-risk surfaces (auth, schema/migrations, websocket lifecycle, security-sensitive code, or anything listed in the project's `## Codex Check Triggers` section).
- **Output triage** — group findings by severity, surface BLOCKERs first, push back honestly when Codex is wrong.
- **Per-project setup** via `/codex-check-setup` — Claude analyzes your repo and drafts a `## Codex Check Triggers` section in your `CLAUDE.md`.
- **Subagent compatibility** — works inside `superpowers:subagent-driven-development` workflows (per-task fire + post-integration fire).

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

Builds on [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc), the official OpenAI plugin that wraps the [Codex CLI](https://github.com/openai/codex) for Claude Code.
