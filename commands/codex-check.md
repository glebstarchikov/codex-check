---
description: Run a 3-axis Codex review (bugs / intent / invariant fit) on the current diff via the codex CLI
allowed-tools: Bash, Read
---

Execute the codex-check flow defined in the codex-check skill (`~/.claude/skills/codex-check/SKILL.md`). Steps:

1. Read the project's CLAUDE.md (if present) and extract its `## Codex Check Triggers` section. Use the surfaces relevant to the current diff.
2. Summarize the user's stated intent for this session in 1–3 sentences. **Include any other working-tree changes** (not just the immediate edit) so Codex's intent-match axis sees the full diff context.
3. Build the focus text covering three review axes (BUGS / INTENT MATCH / INVARIANT FIT) per the skill instructions.
4. Locate the codex CLI (PATH first, then `$HOME/.npm-global/bin`, `$HOME/.bun/bin`, `$HOME/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`). If not found, surface the install hint and stop:
   ```
   codex CLI not found. Install: npm i -g @openai/codex && codex login
   ```
5. Run codex via Bash with the focus text:
   ```bash
   "$CODEX_BIN" exec --skip-git-repo-check <<'EOF'
   You are an adversarial code reviewer. Run `git diff` and `git diff --stat` in the current working directory to see uncommitted changes, then review.

   <focus text from step 3>

   Be concise. Only report findings that materially matter; do not invent issues.
   EOF
   ```
6. Triage the returned findings by severity and surface a summary per the skill's triage rules. Push back honestly when you disagree with a finding.

**Do NOT emit a `/codex:...` slash command** — Claude Code does not auto-route model-emitted slash commands; they appear as text only. The Bash invocation above is the actual primitive `/codex:adversarial-review` itself wraps.

**Optional user-provided steering text:** anything the user typed after `/codex-check` (e.g., `/codex-check verify the cache invalidation logic`) is appended to the focus text *after* the 3 default axes — same pattern as `/codex:adversarial-review`'s focus argument.

**Branch-level review:** if the user invokes `/codex-check --base main` or similar, instruct codex in the prompt to `git diff main...HEAD` instead of the default uncommitted diff — there's no `--base` flag in our wrapper, but the prompt can direct the agent.
