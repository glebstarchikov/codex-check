# codex-check

> A [Claude Code](https://claude.com/claude-code) plugin that adds auto-trigger boundaries, output triage, and per-project setup around the [OpenAI Codex CLI](https://github.com/openai/codex), so Claude reaches for a second-opinion review on the work that matters.

**codex-check** calls `codex` directly. It does not require the [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) Claude Code plugin (though they coexist fine — install both if you also want interactive `/codex:review`, `/codex:rescue`, etc.).

## What you get

- **Auto-trigger** — Claude fires Codex review automatically on complex debugging or high-risk diffs (auth, migrations, websocket lifecycle, anything you list in your project's `CLAUDE.md`).
- **`/codex-check`** — manual invocation with optional `--base <ref>` for branch review and free-text steering.
- **`/codex-check-setup`** — one-time per-repo: Claude analyzes your codebase and drafts a `## Codex Check Triggers` section into `CLAUDE.md` listing the surfaces that should auto-fire.
- **Output triage** — findings grouped by `[BLOCKER]/[CONCERN]/[NIT]`, disagreements surfaced explicitly (no dutiful agreement).
- **Subagent integration** — works inside `superpowers:subagent-driven-development` flows: per-task fire in the subagent's worktree, post-integration fire on the parent's merged diff.

## Prerequisites

- [Claude Code](https://claude.com/claude-code)
- The [`codex` CLI](https://github.com/openai/codex), installed and authenticated. ChatGPT subscription (Plus / Team / Enterprise) or OpenAI API key.

## Install

**Step 1 — install the codex CLI** (once globally):

```bash
npm install -g @openai/codex
codex login          # OAuth via your ChatGPT account
# OR: export OPENAI_API_KEY=sk-...    # in your shell rc, for API-key auth
```

**Step 2 — install codex-check**:

```bash
git clone https://github.com/glebstarchikov/codex-check.git ~/codex-check
cd ~/codex-check
./install.sh
```

`install.sh` symlinks the skill and slash commands into `~/.claude/`. Symlinks (not copies) so `git pull` updates the live install. It also detects the `codex` binary and prints a clear hint if it isn't found — searches `$PATH` first, then `$HOME/.npm-global/bin`, `$HOME/.bun/bin`, `$HOME/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`.

**Manual install** (if you prefer not to run the script):

```bash
ln -s ~/codex-check/skills/codex-check ~/.claude/skills/codex-check
ln -s ~/codex-check/commands/codex-check.md ~/.claude/commands/codex-check.md
ln -s ~/codex-check/commands/codex-check-setup.md ~/.claude/commands/codex-check-setup.md
```

## Configure (once per project)

```bash
cd ~/your-project
# Inside Claude Code:
/codex-check-setup
```

Claude analyzes the repo and proposes a `## Codex Check Triggers` section for your `CLAUDE.md`. Approve, edit, or skip.

If you'd rather write the triggers section by hand, here's a template:

```markdown
## Codex Check Triggers

Fire `/codex-check` (or auto-invoke via the codex-check skill) before
reporting completion when the diff touches any of:

- `path/to/risky/area` — one-line rationale
- `another/risky/path` — why this one matters

**Why these surfaces:** <one paragraph explaining what these have in common — why bugs here are catastrophic vs annoying>.
```

## Usage

**Manual:**

```
/codex-check
/codex-check --base main
/codex-check verify the cache invalidation logic
/codex-check --background --base main
```

**Auto-trigger:**

Claude fires `/codex-check` on its own when it judges the current work matches the skill's trigger criteria (high-risk surfaces from your CLAUDE.md, complex debugging sessions, large multi-file diffs, explicit "double-check" language from you).

## How it works

1. **You or Claude triggers `/codex-check`.**
2. **Skill builds the review context:** the user's stated intent, the project's CLAUDE.md trigger surfaces, the diff.
3. **Skill runs** `codex exec` via Bash, piping in a prompt that tells the agent to `git diff` and review against the 3 axes. Codex returns findings tagged `[BLOCKER]/[CONCERN]/[NIT]` plus a one-line verdict (`SHIP / FIX-FIRST / DISCUSS`).
4. **Claude triages the output:** groups by severity, surfaces BLOCKERs first, evaluates each finding against its own reading of the diff, surfaces disagreements explicitly, asks you which to address.

For branch-level review, the skill includes a "diff against `<base>...HEAD`" instruction in the prompt instead of relying on a CLI flag (the upstream `codex review --uncommitted` is mutually exclusive with custom prompts at the CLI level — bare `codex exec` is the workaround).

## Compatibility

| Skill | Relationship |
|---|---|
| `superpowers:subagent-driven-development` | Per-task fire in subagent worktrees + post-integration fire on parent merge. |
| `superpowers:verification-before-completion` | Complementary. Verification = "did tests/typecheck/build pass." codex-check = "did the diff introduce bugs / drift from intent / regress invariants." Both can fire on the same change. |
| `superpowers:receiving-code-review` | Invoked from codex-check's triage flow when findings are non-trivial. |

### Optional: alongside `openai/codex-plugin-cc`

codex-check has **no hard dependency** on the official OpenAI plugin — both call the same `codex` CLI. If you also install `openai/codex-plugin-cc`, you get a complementary set of interactive slash commands that play well alongside ours:

| Upstream command | When to use |
|---|---|
| `/codex:review` / `/codex:adversarial-review` | Manually fire a Codex review with the upstream's interactive UX (streaming output, follow-up prompts). |
| `/codex:rescue` | Delegate a *task* (investigation, fix attempt) to Codex — different use case from review. |
| `/codex:status` / `/codex:result` / `/codex:cancel` | Manage in-flight Codex background jobs (queued by `--background` from `/codex:adversarial-review`). |
| `/codex:setup --enable-review-gate` | Stop-hook that auto-fires Codex on every Claude turn — drains quota fast; opt-in only. |

## Limitations

- Uses your Codex usage quota (ChatGPT subscription quota or OpenAI API tokens).
- ~30–90s latency per synchronous call (longer for big diffs).
- Requires a git repo (uses `git diff` for diff scoping).
- v0.1.0 runs synchronously only. Background mode is on the roadmap; for now, install `openai/codex-plugin-cc` alongside if you need `--background` behavior on large diffs.

## Uninstall

```bash
~/codex-check/uninstall.sh
```

Removes the three symlinks. Does not touch the upstream codex plugin or your project CLAUDE.md.

## Contributing

Issues and PRs welcome. The full design lives at [docs/design.md](docs/design.md).

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

Builds on [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc), the official OpenAI plugin that wraps the [Codex CLI](https://github.com/openai/codex) for Claude Code. Without their primitives, this plugin would have to reimplement diff scoping, codex invocation, and the entire app-server bridge.
