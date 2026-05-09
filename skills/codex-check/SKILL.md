---
name: codex-check
description: Use after completing complex debugging sessions, multi-file refactors, or any change touching high-risk surfaces — auth, schema/migrations, security-sensitive code, realtime/websocket lifecycle, infrastructure config, or anything where a silent bug would have outsized blast radius. Invokes the OpenAI Codex CLI as a second-opinion reviewer on the diff, checking for bugs, intent drift, and violations of project conventions. Also use when the user explicitly asks to "double-check," "verify with codex," or runs /codex-check. Read the project's CLAUDE.md "## Codex Check Triggers" section (if present) for the project-specific risk-surface list; project-specific entries augment the generic defaults above.
---

# codex-check

Calls the OpenAI Codex CLI directly (via Bash) for a second-opinion review on the current diff. Three review axes: bugs / intent match / invariant fit. Output is triaged by severity and presented to the user with disagreements surfaced explicitly.

**Prerequisite:** the `codex` CLI must be installed and authenticated. If `command -v codex` doesn't resolve and none of the fallback paths in `install.sh` find the binary, stop and direct the user to:

```
npm install -g @openai/codex
codex login    # OAuth via ChatGPT account, or set OPENAI_API_KEY
```

Do not attempt to install or repair codex yourself. The `openai/codex-plugin-cc` Claude Code plugin is **not required** — it bundles the same `codex` CLI but adds Claude Code slash commands that we don't depend on. Users may install it for interactive `/codex:review` etc., but codex-check works without it.

## When to fire

Auto-fire (without being asked) when the current work meets any of:

- The diff touches a surface listed in this project's `CLAUDE.md` `## Codex Check Triggers` section
- Generic high-risk surfaces: auth/session/OAuth/JWT, schema migrations, realtime/websocket/SSE handlers, webhook handlers, payment integration, env validation, security-sensitive code (CSRF, CORS, sanitization, encryption), infrastructure config affecting runtime
- Generic complexity signals: diff over ~150 lines, ≥4 files changed, the session resolved a test failure or runtime bug
- Explicit user language: "double-check," "verify with codex," "second opinion," "run codex on this"
- The user typed `/codex-check`

Do **not** auto-fire on:

- Documentation-only changes
- Pure rename / format / lint fix
- Single-line bugfixes with passing tests
- Trivial dependency bumps
- Within 1–2 turns after a previous codex-check fire on the same diff (anti-recursion)

## Flow

### 1. Build the intent block

In 1–3 sentences, summarize what the user asked for in this session. Codex needs this for the intent-match axis. Example:

> "User asked to fix a race condition where two concurrent webhook posts could double-charge a customer. Fix should ensure the same `payment_id` is processed at most once."

### 2. Build the focus text

Read project `CLAUDE.md` (if present) and extract the `## Codex Check Triggers` section. Include the relevant subset (the surfaces the diff touched) in the focus text so Codex knows what conventions to check.

Construct focus text in this shape:

```
focus on three axes:
(1) BUGS — race conditions, null hazards, off-by-one, security issues, edge cases the change drops.
(2) INTENT MATCH — user asked: "<intent block from step 1>". Did the diff actually solve that, or solve an adjacent problem? Did scope drift?
(3) INVARIANT FIT — does it respect project conventions? Specifically check: <relevant trigger surfaces from CLAUDE.md>.

Output severity-tagged findings: [BLOCKER]/[CONCERN]/[NIT]. End with a one-line verdict: SHIP / FIX-FIRST / DISCUSS.
```

### 3. Invoke codex via Bash

codex-check calls the Codex CLI directly. **Do NOT emit a `/codex:...` slash command** — Claude Code does not auto-route model-emitted slash commands; they appear as text only.

Locate the codex binary (PATH first, then standard install dirs — Bash tool sessions often miss `~/.npm-global/bin` and similar):

```bash
CODEX_BIN="$(command -v codex 2>/dev/null || true)"
if [[ -z "$CODEX_BIN" ]]; then
  for c in "$HOME/.npm-global/bin/codex" "$HOME/.bun/bin/codex" "$HOME/.local/bin/codex" "/opt/homebrew/bin/codex" "/usr/local/bin/codex"; do
    [[ -x "$c" ]] && CODEX_BIN="$c" && break
  done
fi
[[ -z "$CODEX_BIN" ]] && { echo "codex not found — run: npm i -g @openai/codex && codex login"; exit 2; }
```

If `$CODEX_BIN` is empty, surface the install hint (above) and stop. Don't try to install codex yourself.

Run codex with the focus text (the agent runs `git diff` itself to see the uncommitted diff):

```bash
"$CODEX_BIN" exec --skip-git-repo-check <<'EOF'
You are an adversarial code reviewer. Run `git diff` and `git diff --stat` in the current working directory to see uncommitted changes, then review.

<focus text from step 2>

Be concise. Only report findings that materially matter; do not invent issues.
EOF
```

**Why this exact incantation:**
- `codex exec` (bare, no `review` subcommand) lets us pass a custom prompt via stdin — the agent reads `git diff` itself inside the conversation. The `codex review --uncommitted` subcommand is mutually exclusive with custom prompts at the CLI level (real upstream UX bug); this works around it.
- `--skip-git-repo-check` avoids a tripwire when codex is invoked from a subdirectory of the repo.
- Heredoc with `'EOF'` (single-quoted) prevents the shell from expanding `$` references inside the prompt.

**Branch-level review** (e.g., before opening a PR): instead of `--base`, tell the agent in the prompt to diff against a base. Add a line like: *"Run `git diff main...HEAD` to see all changes on this branch, then review."*

**Large diffs:** if `git diff --shortstat HEAD` reports >500 lines or >10 files, the synchronous run will block ~1–3 minutes. v0.1.0 doesn't support background mode (codex CLI's `&` shell-backgrounding loses the session ID needed to retrieve results). Document the wait time to the user before firing.

### 4. Triage output

When Codex returns findings:

1. Parse severity tags. Group by `[BLOCKER]` → `[CONCERN]` → `[NIT]`.
2. Surface a structured summary to the user:
   - BLOCKERs first: file:line + one-sentence what + one-sentence why.
   - Top 3 CONCERNs likewise.
   - NITs collapsed into a count: "+ 7 nits available — ask for details if you want them."
3. Quote Codex's verdict line (`SHIP / FIX-FIRST / DISCUSS`) prominently.
4. Evaluate each finding against your own reading of the diff *before* defaulting to "agree." If a finding is incorrect (Codex misread the diff, suggested fix violates project conventions, finding is out of scope), surface the disagreement explicitly with reasoning.
5. Default offer to user: "Address all valid BLOCKERs and CONCERNs; <N> findings I disagree with — here's why: …; <N> NITs deferred." Ask which to fix.
6. If the findings are non-trivial (multiple BLOCKERs or significant disagreements), invoke `superpowers:receiving-code-review` for the disciplined feedback-handling flow.

### 5. Anti-recursion

Do not re-fire codex-check in the next 1–2 turns on the same diff. Re-fire is allowed once you've addressed findings and produced a meaningfully new diff.

## When dispatched as a subagent

If you were dispatched by `superpowers:subagent-driven-development` and your task touched a high-risk surface, fire codex-check (run the codex incantation from step 3) in your worktree *before* reporting completion.

- Address all [BLOCKER] and [CONCERN] findings you agree with directly — fix and re-test.
- Surface [NIT]s and any disagreements in your completion report to the parent.
- Skip step 4's "ask user which to fix" — the parent triages.

The parent should run codex-check again on the integration branch's full diff (instruct codex to `git diff <integration-base>...HEAD` in the prompt) after merging all subagents, to catch integration-level issues that no single subagent's review could have spotted.

## What this skill does NOT do

- Install or authenticate codex CLI — direct the user to `npm i -g @openai/codex && codex login` if it's missing.
- Wrap `openai/codex-plugin-cc` slash commands — codex-check calls the `codex` CLI directly via Bash; the upstream plugin is optional and can be used alongside for interactive `/codex:review` etc.
- Modify code — codex-check is read-only review; user decides what to fix.
- Run tests / typecheck / build — that's `superpowers:verification-before-completion`. Both can fire on the same change; they catch different bug classes.
