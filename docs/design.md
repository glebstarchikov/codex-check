# codex-check — wrapper plugin for second-opinion review via Codex CLI

> Status: design / pending implementation
> Authoring conversation: 2026-05-03
> Owner: Gleb
> Distribution target: public GitHub repo, installable via Claude Code's `/plugin install` mechanism

---

## 1. Problem

When Claude Code finishes complex work — debugging sessions, multi-file refactors, changes to high-risk surfaces (DB schema, auth, websocket lifecycle, migrations) — there's no automatic second pair of eyes. Self-review by the same model has known blind spots: bugs the model didn't see while writing, intent drift where the diff solves an adjacent problem instead of the stated one, silent regressions of project conventions.

A "different model with a different prior" review catches the things self-review misses. OpenAI's Codex CLI provides exactly this, and the official `openai/codex-plugin-cc` plugin already exposes it inside Claude Code as `/codex:review` and `/codex:adversarial-review`.

What's missing is the **orchestration layer**:

- **When to fire it.** Today the user has to remember. We want Claude to auto-invoke on high-risk surfaces and complex debugging, with manual override always available.
- **Project-specific risk surfaces.** The notion of "high-risk" is repo-specific. Guia's Phase 3A invariants (`tenantDb` usage, composite FKs, migration ordering) are catastrophic if regressed; in another repo the high-risk surfaces are different.
- **Output triage.** Codex returns review findings; we want grouped severity, summary, and the discipline to push back when Codex is wrong rather than blindly implementing every finding.
- **Subagent integration.** With `superpowers:subagent-driven-development`, parallel subagents finish work in isolated worktrees. Per-task review (in the subagent's worktree, before reporting) and post-integration review (on the parent's merged diff) catch different bug classes.
- **Per-project setup.** Each repo needs a `## Codex Check Triggers` section in its CLAUDE.md. Claude can analyze the codebase and draft this once per repo.

This spec defines a thin wrapper plugin that adds these layers on top of `openai/codex-plugin-cc`.

## 2. Non-goals

- Reimplementing what the official plugin already provides: codex install/auth, diff scoping, the review prompt itself, background-task delegation, output retrieval, app-server bridge.
- Replacing `/codex:review` or `/codex:adversarial-review` — we call them.
- Forking `openai/codex-plugin-cc`. Decided against (see §10 rejected alternatives).
- Building our own codex-CLI invocation, bash script, install script for codex itself, or preflight logic for codex auth.

## 3. Architecture

### 3.1 Dependency relationship

```
codex-check (this plugin)
    └── depends on → openai/codex-plugin-cc
                         └── depends on → @openai/codex (CLI binary)
```

Two `/plugin install` commands during onboarding. Clean dependency direction: every upstream improvement to `openai/codex-plugin-cc` is inherited automatically. No fork, no merge debt.

### 3.2 Repo layout

```
codex-check/
├── README.md                   ← prerequisites, install, setup, usage, configuration, limitations
├── LICENSE                     ← MIT
├── install.sh                  ← symlinks skills/ and commands/ into ~/.claude/
├── uninstall.sh                ← removes those symlinks
├── skills/
│   └── codex-check/
│       └── SKILL.md            ← auto-trigger description + flow + subagent guidance
└── commands/
    ├── codex-check.md          ← thin wrapper around /codex:adversarial-review with our default focus text
    └── codex-check-setup.md    ← per-project triggers drafter
```

Three files of real content (SKILL.md plus two slash-command markdown files). Install script is small and dumb (symlinks only — no codebase analysis, no codex install).

### 3.3 Lifecycle

**Install (once globally):**
1. `/plugin marketplace add openai/codex-plugin-cc`
2. `/plugin install codex@openai-codex`
3. `/codex:setup` — runs the official plugin's install/auth check; prompts user through `codex login` if needed.
4. `git clone <our-repo> && cd codex-check && ./install.sh` — symlinks our skill + commands into `~/.claude/`.

**Configure (once per repo):**
1. `cd ~/your-project`
2. `/codex-check-setup` — Claude reads project files (CLAUDE.md, top-level dirs, package.json, recent commits), proposes a `## Codex Check Triggers` section listing this repo's high-risk surfaces with rationale, asks for approval, writes to CLAUDE.md (creates the file if missing).

**During work:**
- **Auto-trigger:** Claude judges that the current work matches the SKILL.md description (debugging, multi-file refactor, high-risk surface from CLAUDE.md's trigger section, explicit "double-check" / "verify" language) and fires `/codex-check`.
- **Manual:** user types `/codex-check` explicitly.
- Both paths invoke `/codex:adversarial-review` with focus text covering the three review axes (§4.2).
- Claude reads Codex output, groups findings by `[BLOCKER]/[CONCERN]/[NIT]`, presents summary, asks which to address. Pushes back honestly on findings it disagrees with.

## 4. Component specifications

### 4.1 `skills/codex-check/SKILL.md`

**Frontmatter description (the auto-trigger surface):**

```yaml
---
name: codex-check
description: |
  Use after completing complex debugging sessions, multi-file refactors,
  or any change touching high-risk surfaces — auth, schema/migrations,
  security-sensitive code, realtime/websocket lifecycle, infrastructure
  config, or anything where a silent bug would have outsized blast radius.
  Invokes the OpenAI Codex CLI as a second-opinion reviewer on the diff,
  checking for bugs, intent drift, and violations of project conventions.
  Also use when the user explicitly asks to "double-check," "verify with
  codex," or runs /codex-check. Read the project's CLAUDE.md "## Codex
  Check Triggers" section (if present) for project-specific risk-surface
  list; those override the generic defaults above.
---
```

**Body sections (instructions to the model when invoked):**

1. **Preflight reminder.** If `/codex:adversarial-review` exits with an install/auth error, surface the error verbatim and stop. Do not try to fix the user's codex install. Direct them to `/codex:setup`.
2. **Intent assembly.** Before invoking, summarize the user's stated intent in 1–3 sentences (what they asked for in the current session). Pass it as part of the focus text to `/codex:adversarial-review`. Codex needs this for the intent-match axis.
3. **Trigger surfaces.** Read project CLAUDE.md's `## Codex Check Triggers` section if present. Pass relevant surfaces as part of the focus text so Codex knows what conventions to check the diff against.
4. **Invocation pattern.** Default invocation:
   ```
   /codex:adversarial-review focus on three axes:
   (1) BUGS — race conditions, null hazards, off-by-one, security issues, edge cases the change drops;
   (2) INTENT MATCH — user asked: "<intent>". Did the diff actually solve that, or solve an adjacent problem? Did scope drift?
   (3) INVARIANT FIT — does it respect project conventions in CLAUDE.md? Specifically: <relevant trigger surfaces>.
   Output severity-tagged findings: [BLOCKER]/[CONCERN]/[NIT]. End with a one-line verdict: SHIP / FIX-FIRST / DISCUSS.
   ```
5. **Output triage.** Read findings, group by severity, present BLOCKERs first, then CONCERNs with file:line, then collapse NITs into a count. Ask the user which to address before touching code.
6. **Push back honestly.** When Codex flags something incorrect, out of scope, or based on a misreading, say so explicitly. Invoke `superpowers:receiving-code-review` if the findings are non-trivial.
7. **Subagent mode.** If dispatched as a subagent on a high-risk task, fire `/codex-check` *before* reporting completion. Address [BLOCKER]/[CONCERN] findings in-place; surface [NIT]s in the completion report. Skip the "ask user which to address" step — instead, address what's clearly correct and report findings up.
8. **Anti-recursion.** If you just fired `/codex-check` this turn or last turn and got results, do not fire again on the same diff. One review per change.

### 4.2 `commands/codex-check.md`

Markdown command file. Its body is the prompt Claude executes when the user types `/codex-check`. The body invokes the same flow defined in SKILL.md §4.1 body, plus passes through any user-provided arguments. Two argument shapes supported:

- `/codex-check --base <ref>` — passed through to `/codex:adversarial-review --base <ref>` for branch review.
- `/codex-check <free text>` — appended to the focus text *after* the 3 default axes, so the user can steer Codex toward a specific concern (e.g., `/codex-check verify the cache invalidation logic`).

The slash-command body is short — most of the flow lives in SKILL.md and is referenced. Exact frontmatter field names and argument-passing semantics are confirmed against current Claude Code command spec at implementation time (§12 open question).

### 4.3 `commands/codex-check-setup.md`

Per-project triggers drafter. Markdown command that instructs Claude to:

1. Detect repo root (`git rev-parse --show-toplevel`).
2. Read existing `CLAUDE.md` (if present), `README.md`, top-level directory structure, `package.json` scripts, last 20 commit subjects.
3. Identify likely high-risk surfaces by pattern:
   - DB schema, migrations, ORM tenant primitives
   - Auth code, session handling, password hashing
   - Realtime / websocket / streaming handlers
   - Webhook handlers, payment integration
   - Env validation
   - Anything explicitly flagged "invariant," "must not regress," "load-bearing" in existing CLAUDE.md
4. Propose a `## Codex Check Triggers` section with file paths + one-line rationale per surface.
5. Show the proposed section to the user, ask for approval/edits.
6. On approval, append to existing `CLAUDE.md` or create the file. If the section already exists, propose a diff instead of overwriting.
7. Idempotent — running twice with no changes should be a no-op.

### 4.4 `install.sh`

Idempotent symlink installer:

```
1. Detect ~/.claude/ exists (create if missing).
2. Create ~/.claude/skills/ and ~/.claude/commands/ if missing.
3. Symlink skills/codex-check/  →  ~/.claude/skills/codex-check
4. Symlink commands/codex-check.md  →  ~/.claude/commands/codex-check.md
5. Symlink commands/codex-check-setup.md  →  ~/.claude/commands/codex-check-setup.md
6. Detect if openai/codex-plugin-cc is installed (~/.claude/plugins/cache/openai/codex-plugin-cc/ or similar). If not, print a one-line note pointing the user to /plugin install codex@openai-codex.
7. Idempotent: re-running the script should not error if links already exist; replace if pointing elsewhere.
```

`uninstall.sh` removes the same three symlinks; does not touch the upstream codex plugin.

### 4.5 `README.md`

Sections:

1. **What it is.** One paragraph describing codex-check as a wrapper that adds auto-trigger boundaries, output triage, and per-project setup on top of `openai/codex-plugin-cc`.
2. **Why use it.** Different-model second opinion on debugging and high-risk work. Avoids over-firing through trigger boundaries.
3. **Prerequisites.** Claude Code; `openai/codex-plugin-cc` installed and `/codex:setup` complete (ChatGPT subscription or OpenAI API key).
4. **Install.** Two-step: `/plugin install codex@openai-codex` then `git clone … && ./install.sh`.
5. **Configure each project.** Run `/codex-check-setup` once per repo. Includes a copy-pasteable `## Codex Check Triggers` template for users who prefer to write it manually.
6. **Usage.** `/codex-check`, `/codex-check --base main`, `/codex-check <focus text>`, plus the auto-trigger description.
7. **How it works.** The lifecycle from §3.3, briefly.
8. **Compatibility.** Short notes on `superpowers:subagent-driven-development` (per-task fire + post-integration fire), `superpowers:verification-before-completion` (complementary; codex-check is review, verification is "did tests pass"), `superpowers:receiving-code-review` (codex-check explicitly invokes it on non-trivial findings).
9. **Limitations.** Uses Codex usage quota; ~30–90s latency per call; requires a git repo; review-gate option (from upstream) is not enabled by default — opt-in via `/codex:setup --enable-review-gate`.
10. **Contributing / License (MIT) / Acknowledgments** (link to `openai/codex-plugin-cc` upstream).

## 5. Subagent-driven-development integration

Two complementary fire points, both documented in SKILL.md:

**Per-subagent fire.** When a subagent dispatched by `superpowers:subagent-driven-development` is working on a high-risk task (touches a surface in CLAUDE.md's trigger section), it fires `/codex-check` in its worktree before reporting completion. The subagent addresses [BLOCKER]/[CONCERN] findings itself and surfaces [NIT]s to the parent. This catches bugs while they're still cheap to fix in the subagent's isolated workspace.

**Post-integration fire.** After all subagents merge into the parent's integration branch, the parent fires `/codex-check --base <integration-base>` on the combined diff. This catches semantic conflicts between subagents that no single subagent's review would have spotted (duplicate utilities, contradictory schema migrations, conflicting assumptions).

**Cost reasoning.** Two fires (per-subagent + post-integration) is ~$0.20–0.40 of subscription quota, ~2 minutes of latency. Acceptable for the kind of work that triggers codex-check in the first place. Trivial subagent work doesn't fire codex-check at all because the trigger description rules it out.

## 6. Project-specific configuration via CLAUDE.md

The skill description tells Claude to read project `CLAUDE.md`'s `## Codex Check Triggers` section. The section is the canonical home for project-specific risk surfaces because:

- It travels with the repo (visible to teammates, picked up automatically by Claude in any session).
- It's read by `/codex:adversarial-review` as part of project context.
- It's the same surface used by the focus text we pass to Codex for invariant-fit review.

Memory entries (per-user `~/.claude/projects/<hash>/memory/`) are deliberately *not* used for trigger lists. Memory is local-only and doesn't travel with the repo, so it can't serve teammates or other plugin users. Memory remains the right surface for personal cross-project preferences (covered by §11 future work).

For Guia specifically, running `/codex-check-setup` will propose a `## Codex Check Triggers` section listing:

- `db/schema.ts`, `db/migrations/`, `db/tenant.ts`, `db/admin.ts`
- Any file importing `tenantDb` or `adminDb` (Phase 3A invariant #22)
- `server/routes/_ws.ts` — WS session lifecycle
- `server/utils/gemini/*` — upstream Gemini Live, session manager
- `server/utils/env.ts` — env validation
- `server/middleware/tenant.ts` (Phase 3D+) — subdomain → tenant context
- Auth, billing, rate-limiting code (as those phases ship)

Each with a one-line rationale tied to the Phase 3A invariants. Approval/edit by the user before write.

## 7. Trigger taxonomy (what fires the skill)

The SKILL.md description fires Claude's auto-invocation when *any* of:

**Generic high-risk surfaces (apply in any repo):**
- Auth, session, password, OAuth, JWT code
- Schema migrations, DDL, ORM tenant primitives
- Realtime / websocket / SSE / streaming handlers
- Webhook handlers, payment integration code
- Environment validation, secret loading
- Security-sensitive code (CSRF, CORS, sanitization, encryption)
- Infrastructure config (Dockerfile, fly.toml, deploy scripts) on changes that affect runtime

**Project-specific surfaces (from CLAUDE.md `## Codex Check Triggers`):**
- Whatever the project's `/codex-check-setup` produced.

**Generic complexity signals:**
- Diff over ~150 lines or touches ≥4 files
- Session that included resolving a test failure or runtime bug
- Explicit user language: "double-check," "verify," "make sure," "second opinion"

**Anti-trigger (don't fire):**
- Documentation-only changes
- Pure rename / formatting / lint fix
- Single-line bug fixes with passing tests
- Trivial dependency bumps

The boundary errs on the side of *not* firing. Under-fire is recoverable (`/codex-check` manual). Over-fire burns subscription quota and slows iteration.

## 8. Output handling

When `/codex:adversarial-review` returns its review:

1. **Group findings by severity.** Parse the `[BLOCKER]/[CONCERN]/[NIT]` tags. Count NITs separately to avoid drowning the summary.
2. **Surface a structured summary.** BLOCKERs first with file:line and one-sentence what+why. Top 3 CONCERNs likewise. NITs collapsed to a count with "ask if you want details."
3. **Verdict line.** Show Codex's `SHIP / FIX-FIRST / DISCUSS` verdict prominently.
4. **Triage prompt.** Ask the user which findings to address. For each finding, Claude evaluates it against its own reading of the diff before defaulting to "agree." Surface explicit disagreements (Codex misread the code, suggested fix violates project conventions, finding is out of scope) rather than silently dropping or silently accepting. Default offer to user: address all BLOCKERs Claude considers valid; address CONCERNs Claude considers valid; surface disagreements with rationale.
5. **Push back when wrong.** If a finding is incorrect (Codex misread the diff, hit a known false-positive pattern, suggested a fix that violates project conventions), say so directly. Don't dutifully implement findings to seem agreeable. Invoke `superpowers:receiving-code-review` for non-trivial pushback.
6. **Anti-recursion.** Don't fire `/codex-check` again on the same diff in the immediate next turn. One review per change. (Re-fire allowed after addressing findings and producing a new diff.)

## 9. Compatibility with existing superpowers skills

| Skill | Relationship |
|---|---|
| `superpowers:subagent-driven-development` | Per-task + post-integration fire pattern (§5). |
| `superpowers:verification-before-completion` | Complementary, not duplicative. Verification = "did tests/typecheck/build pass" (deterministic). codex-check = "did I introduce bugs / drift from intent / regress invariants" (model-judged). Both can fire on the same change. |
| `superpowers:receiving-code-review` | Invoked from codex-check's output triage when findings are non-trivial. The "push back honestly" rule comes directly from this skill's principles. |
| `superpowers:requesting-code-review` | Not invoked. That skill is for human review (e.g., before opening a PR). codex-check is for AI second-opinion mid-flow. |
| `superpowers:systematic-debugging` | If the user is in a debugging session, codex-check fires after the bug is fixed (validates the fix doesn't introduce a new bug or miss the root cause). |

## 10. Rejected alternatives

**Fork `openai/codex-plugin-cc`.**
Rejected. Our value-add (auto-trigger, triage, per-project setup) lives *above* their layer, not inside it. Forking would inherit hundreds of lines of TypeScript app-server bridge code we'd have to maintain forever for zero functional gain. Every upstream commit would become a merge. The upstream is actively maintained by OpenAI; we want their `/codex:adversarial-review` exactly as-is. Wrapper is the structurally correct choice.

**Build our own bash script + codex invocation (original draft).**
Rejected after discovering `openai/codex-plugin-cc`. Reimplementing diff scoping, prompt assembly, codex-CLI invocation, install/auth preflight is exactly what the official plugin already does. Doing it ourselves would mean maintaining duplicate code that drifts from upstream codex CLI changes.

**Save trigger lists in per-user memory.**
Rejected because memory is local-only and doesn't travel with the repo. Triggers are project-public policy that teammates and other plugin users should see — CLAUDE.md is the right surface. Memory is reserved for personal cross-project preferences.

**Stop hook auto-firing on every turn (review gate).**
The official plugin already provides this via `/codex:setup --enable-review-gate`. We don't replicate. Default is off because it drains subscription quota. Users who want it can opt in via the upstream switch; our value is the smarter middle (model-judged trigger boundary).

**One slash command for both fire and setup (`/codex-check init` subcommand).**
Rejected for discoverability. Two separate commands (`/codex-check`, `/codex-check-setup`) are easier to find via Claude Code's command listing and easier to document.

## 11. Out of scope (future work)

- **Memory entry for personal cross-project preferences.** Optional pattern: a per-user memory note that says "always fire codex-check on changes I make to docs/copy" or similar. Not in v1; users can write this manually if useful.
- **Upstream PR.** If the auto-trigger pattern proves out, propose merging the skill into `openai/codex-plugin-cc` directly. Cleaner end-state, requires upstream agreement.
- **Plugin-format conversion.** v1 ships as plain skill repo with install script. Converting to a full Claude Code plugin (with `package.json`, `marketplace.json`, version-bump workflow) is a small refactor; revisit after traction.
- **Built-in trigger templates.** Curated `## Codex Check Triggers` sections for common stacks (Next.js, Rails, Django, etc.) that `/codex-check-setup` can offer as starting points. Useful at scale; not blocking v1.
- **Cost telemetry.** Track approximate quota usage per fire and surface to user (e.g., "this review used ~5% of weekly quota"). Out of scope for v1; may not be possible without upstream support.

## 12. Open questions for implementation

These are deferred to the implementation plan, not blockers for the spec:

1. **Exact slash-command frontmatter** for Claude Code commands — verify field names (`name`, `description`, `model`, etc.) and argument-passing semantics from current Claude Code docs.
2. **How to detect `openai/codex-plugin-cc` installation** in `install.sh` — pathing under `~/.claude/plugins/cache/` or similar.
3. **Behavior of `/codex:adversarial-review` focus-text passing** — confirm focus text is appended to the prompt as additional context (vs. replacing it), and that multi-line focus text is supported.
4. **Anti-recursion mechanism** — how Claude knows it just fired the skill (in-conversation memory? a marker file? skill-internal flag?). Likely just convention in SKILL.md ("if you fired this in the last 1–2 turns, don't re-fire"); investigate if anything stronger is needed.

## 13. Acceptance criteria

A v1 ship is acceptable when:

- [ ] Repo public on GitHub with MIT license, README covering all sections in §4.5.
- [ ] `install.sh` symlinks the skill + two commands into `~/.claude/`, idempotent, prints clear status.
- [ ] `uninstall.sh` removes them cleanly.
- [ ] `/codex-check` fires `/codex:adversarial-review` with the 3-axis focus text and triages output by severity.
- [ ] `/codex-check-setup` proposes a `## Codex Check Triggers` section for the current repo, asks for approval, writes to CLAUDE.md.
- [ ] SKILL.md description is generic enough to fire correctly in repos other than Guia.
- [ ] Manual end-to-end test in Guia: `/codex-check-setup` produces a sensible Phase 3A trigger list; `/codex-check` returns a usable review on a non-trivial diff.
- [ ] Manual test in a second repo (any side project) confirms portability.
- [ ] README acknowledges `openai/codex-plugin-cc` upstream.
