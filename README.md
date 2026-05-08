# codex-check

> A wrapper plugin for [Claude Code](https://claude.com/claude-code) that adds auto-trigger boundaries, output triage, and per-project setup on top of [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc).

The official OpenAI plugin gives Claude Code users `/codex:review` and `/codex:adversarial-review`. **codex-check** sits above those primitives so Claude knows *when* to invoke them on its own work, and how to triage what comes back.

## What you get

- **Auto-trigger** — Claude fires Codex review automatically on complex debugging or high-risk diffs (auth, migrations, websocket lifecycle, anything you list in your project's `CLAUDE.md`).
- **`/codex-check`** — manual invocation with optional `--base <ref>` for branch review and free-text steering.
- **`/codex-check-setup`** — one-time per-repo: Claude analyzes your codebase and drafts a `## Codex Check Triggers` section into `CLAUDE.md` listing the surfaces that should auto-fire.
- **Output triage** — findings grouped by `[BLOCKER]/[CONCERN]/[NIT]`, disagreements surfaced explicitly (no dutiful agreement).
- **Subagent integration** — works inside `superpowers:subagent-driven-development` flows: per-task fire in the subagent's worktree, post-integration fire on the parent's merged diff.

## Prerequisites

- [Claude Code](https://claude.com/claude-code)
- [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) installed and authenticated. ChatGPT subscription (Plus/Team/Enterprise) or OpenAI API key.

## Install

**Step 1 — install the upstream plugin** (once globally):

```bash
# Inside Claude Code:
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/codex:setup
```

`/codex:setup` walks you through `codex login` if you haven't authenticated yet.

**Step 2 — install codex-check**:

```bash
git clone https://github.com/glebstarchikov/codex-check.git ~/codex-check
cd ~/codex-check
./install.sh
```

This symlinks the skill and slash commands into `~/.claude/`. Symlinks (not copies) so `git pull` updates the live install.

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
3. **Skill calls** `/codex:adversarial-review <focus-text>` (or `--base <ref>` for branch review). Codex returns findings tagged `[BLOCKER]/[CONCERN]/[NIT]`.
4. **Claude triages the output:** groups by severity, surfaces BLOCKERs first, evaluates each finding against its own reading of the diff, surfaces disagreements explicitly, asks you which to address.

## Compatibility

| Skill | Relationship |
|---|---|
| `superpowers:subagent-driven-development` | Per-task fire in subagent worktrees + post-integration fire on parent merge. |
| `superpowers:verification-before-completion` | Complementary. Verification = "did tests/typecheck/build pass." codex-check = "did the diff introduce bugs / drift from intent / regress invariants." Both can fire on the same change. |
| `superpowers:receiving-code-review` | Invoked from codex-check's triage flow when findings are non-trivial. |

### Upstream plugin commands you can use directly

codex-check is a wrapper, not a replacement. These upstream commands from `openai/codex-plugin-cc` work alongside it:

| Command | When to use |
|---|---|
| `/codex:status [job-id]` | Check a background review queued by codex-check (or any other Codex job). |
| `/codex:result [job-id]` | Read findings from a completed background job. codex-check will run this automatically when polling, but you can call it directly. |
| `/codex:cancel [job-id]` | Abort an in-flight background review. |
| `/codex:rescue` | Different use case — delegate a *task* (investigation, fix attempt) to Codex rather than ask for review. Out of scope for codex-check; use upstream directly. |

## Limitations

- Uses your Codex usage quota (ChatGPT subscription quota or OpenAI API tokens).
- ~30–90s latency per call (longer for big diffs; use `--background` for those).
- Requires a git repo (uses `git diff` for diff scoping).
- The `--enable-review-gate` Stop hook (from upstream) is **not** enabled by default. It auto-fires Codex on every Claude turn, which drains quota fast. Enable manually if you want it: `/codex:setup --enable-review-gate`.

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
