---
name: codex-check
description: Use after completing complex debugging sessions, multi-file refactors, or any change touching high-risk surfaces — auth, schema/migrations, security-sensitive code, realtime/websocket lifecycle, infrastructure config, or anything where a silent bug would have outsized blast radius. Invokes the OpenAI Codex CLI as a second-opinion reviewer on the diff, checking for bugs, intent drift, and violations of project conventions. Also use when the user explicitly asks to "double-check," "verify with codex," or runs /codex-check. Read the project's CLAUDE.md "## Codex Check Triggers" section (if present) for the project-specific risk-surface list; project-specific entries augment the generic defaults above.
---

# codex-check

Wrapper that auto-invokes `/codex:adversarial-review` from `openai/codex-plugin-cc` for a second-opinion review on the current diff. Three review axes: bugs / intent match / invariant fit. Output is triaged by severity and presented to the user with disagreements surfaced explicitly.

**Prerequisite:** `openai/codex-plugin-cc` must be installed and authenticated. If it isn't, the `/codex:adversarial-review` invocation below will fail; surface the failure verbatim and direct the user to `/codex:setup`. Do not attempt to install or repair codex yourself.

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

### 3. Invoke `/codex:adversarial-review`

Default invocation passes the focus text:

```
/codex:adversarial-review <focus text>
```

For branch-level review (e.g., before opening a PR), use `--base`:

```
/codex:adversarial-review --base main <focus text>
```

**Auto-background heuristic.** If the diff is large — over ~500 lines OR touching over ~10 files — default to `--background` rather than blocking the conversation for 1–3 minutes. Quick check before invoking:

```bash
git diff --stat <range> | tail -1
# Look at "N files changed, M insertions(+), K deletions(-)"
```

If `N > 10` or `M + K > 500`, run with `--background`. Otherwise run synchronously.

```
/codex:adversarial-review --background <focus text>
```

When you queue a background job, surface the job ID to the user immediately and tell them how to check on it (or that you'll check on it when they come back).

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

### 5. Background-job follow-up

If you queued a background job in step 3, you own the follow-up:

- **Surface the job ID** in your reply: "Codex review queued as background job `task-abc123`. I'll check on it next turn, or you can run `/codex:status` / `/codex:result` directly."
- **Next time the user mentions the review** (or after enough conversation has passed that the job is likely done), run `/codex:status <job-id>`. If still running, tell the user. If completed, run `/codex:result <job-id>` and apply the same triage flow from step 4.
- **Use `/codex:cancel <job-id>`** if the user changes their mind mid-flight (e.g., they've moved on to another problem and don't want to wait).
- **One in-flight at a time** is the simplest mental model — if a previous codex-check job is still pending, surface that and ask whether to cancel before queueing a new one.

### 6. Anti-recursion

Do not re-fire codex-check in the next 1–2 turns on the same diff. Re-fire is allowed once you've addressed findings and produced a meaningfully new diff.

## When dispatched as a subagent

If you were dispatched by `superpowers:subagent-driven-development` and your task touched a high-risk surface, fire `/codex-check` in your worktree *before* reporting completion.

- Address all [BLOCKER] and [CONCERN] findings you agree with directly — fix and re-test.
- Surface [NIT]s and any disagreements in your completion report to the parent.
- Skip step 4's "ask user which to fix" — the parent triages.

The parent should fire a second `/codex-check --base <integration-base>` after merging all subagents to catch integration-level issues that no single subagent's review could have spotted.

## What this skill does NOT do

- Install or authenticate codex CLI — that's `/codex:setup` from the upstream plugin.
- Replace `/codex:review` or `/codex:adversarial-review` — it calls them.
- Modify code — codex-check is read-only review; user decides what to fix.
- Run tests / typecheck / build — that's `superpowers:verification-before-completion`. Both can fire on the same change; they catch different bug classes.
