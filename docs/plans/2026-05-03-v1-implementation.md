# codex-check v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v1 of codex-check — a wrapper plugin for Claude Code that auto-invokes `/codex:adversarial-review` (from `openai/codex-plugin-cc`) on high-risk diffs, triages findings by severity, and provides per-project setup of trigger surfaces in CLAUDE.md.

**Architecture:** Pure markdown + bash. One SKILL.md (auto-trigger description + flow), two slash-command markdown files (`/codex-check`, `/codex-check-setup`), an idempotent `install.sh` that symlinks them into `~/.claude/`, and a matching `uninstall.sh`. Runtime dependency on `openai/codex-plugin-cc`; no codex-CLI invocation of our own.

**Tech Stack:** Bash (POSIX-ish, GNU coreutils OK), Markdown with YAML frontmatter, plain `bash` test harness (no bats/shellspec dependency). `shellcheck` for lint.

**Spec:** See [`docs/design.md`](../design.md) for full design rationale and decisions.

---

## File Structure

```
codex-check/
├── README.md                       ← Modify (Task 8): replace stub with full v1 README
├── LICENSE                         ← Already exists (MIT)
├── .gitignore                      ← Already exists
├── install.sh                      ← Create (Task 2)
├── uninstall.sh                    ← Create (Task 3)
├── tests/
│   ├── lib.sh                      ← Create (Task 1): shared test helpers
│   ├── install.test.sh             ← Create (Task 2)
│   └── uninstall.test.sh           ← Create (Task 3)
├── skills/
│   └── codex-check/
│       └── SKILL.md                ← Create (Task 5)
├── commands/
│   ├── codex-check.md              ← Create (Task 6)
│   └── codex-check-setup.md        ← Create (Task 7)
└── docs/
    ├── design.md                   ← Already exists (the spec)
    └── plans/
        └── 2026-05-03-v1-implementation.md   ← This file
```

**Why this layout:**
- Bash + tests live at repo root for installer concerns. Clear separation from skill/command content.
- `skills/codex-check/SKILL.md` mirrors the layout `~/.claude/skills/<name>/SKILL.md` exactly so the symlink target structure is obvious.
- `commands/*.md` mirrors `~/.claude/commands/*.md` likewise.
- Tests live in `tests/` next to scripts; small, plain bash, easy to read.

---

## Task 1: Test scaffolding + lib.sh

**Files:**
- Create: `tests/lib.sh`
- Create: `tests/.gitkeep` (until first real test file lands; remove after Task 2)

Pure helper file — sets up test isolation primitives reused across `install.test.sh` and `uninstall.test.sh`. No production code yet.

- [ ] **Step 1.1: Create `tests/lib.sh`**

```bash
#!/usr/bin/env bash
# tests/lib.sh — shared helpers for codex-check installer tests.
# All tests use a tempdir as fake $HOME so they never touch the real ~/.claude.

set -euo pipefail

# Repo root, regardless of where the test was invoked from.
TESTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_LIB_DIR/.." && pwd)"

# Create a temp HOME for this test run. Caller must trap cleanup.
make_fake_home() {
  local tmp
  tmp="$(mktemp -d -t codex-check-test.XXXXXX)"
  echo "$tmp"
}

# Run the installer or uninstaller with HOME pointing at the fake dir.
run_with_home() {
  local fake_home="$1"
  local script="$2"
  shift 2
  HOME="$fake_home" bash "$REPO_ROOT/$script" "$@"
}

# Assert: a path exists and is a symlink whose target matches the expected absolute path.
assert_symlink() {
  local link="$1"
  local expected_target="$2"
  if [[ ! -L "$link" ]]; then
    echo "FAIL: $link is not a symlink" >&2
    return 1
  fi
  local actual
  actual="$(readlink "$link")"
  if [[ "$actual" != "$expected_target" ]]; then
    echo "FAIL: $link points to $actual, expected $expected_target" >&2
    return 1
  fi
}

# Assert: a path does NOT exist (used for uninstall checks).
assert_absent() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    echo "FAIL: $path still exists after uninstall" >&2
    return 1
  fi
}

# Pretty pass/fail.
pass() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*" >&2; exit 1; }
```

- [ ] **Step 1.2: Verify the file is syntactically valid bash**

Run: `bash -n /Users/glebstarcikov/codex-check/tests/lib.sh`
Expected: silent (no output, exit 0).

- [ ] **Step 1.3: Commit**

```bash
cd /Users/glebstarcikov/codex-check
git add tests/lib.sh
git commit -m "test: add shared bash test helpers (tests/lib.sh)"
git push
```

---

## Task 2: install.sh — TDD

**Files:**
- Create: `tests/install.test.sh`
- Create: `install.sh`

Build install.sh by writing the test first, watching it fail, implementing the minimum, watching it pass, then iterating for idempotency and the `openai/codex-plugin-cc` detection warning.

- [ ] **Step 2.1: Write `tests/install.test.sh` (failing test — install.sh doesn't exist yet)**

```bash
#!/usr/bin/env bash
# tests/install.test.sh — verify install.sh creates correct symlinks, is idempotent,
# and warns when openai/codex-plugin-cc is missing.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

echo "TEST: install.sh creates expected symlinks"

FAKE_HOME="$(make_fake_home)"
trap 'rm -rf "$FAKE_HOME"' EXIT

run_with_home "$FAKE_HOME" install.sh > /tmp/install-test.out 2>&1 || {
  cat /tmp/install-test.out
  fail "install.sh exited non-zero"
}

assert_symlink "$FAKE_HOME/.claude/skills/codex-check"      "$REPO_ROOT/skills/codex-check"
assert_symlink "$FAKE_HOME/.claude/commands/codex-check.md" "$REPO_ROOT/commands/codex-check.md"
assert_symlink "$FAKE_HOME/.claude/commands/codex-check-setup.md" "$REPO_ROOT/commands/codex-check-setup.md"
pass "all three symlinks present and correct"

echo "TEST: install.sh is idempotent (re-running succeeds)"
run_with_home "$FAKE_HOME" install.sh > /tmp/install-test.out 2>&1 || {
  cat /tmp/install-test.out
  fail "second install.sh run exited non-zero"
}
assert_symlink "$FAKE_HOME/.claude/skills/codex-check" "$REPO_ROOT/skills/codex-check"
pass "idempotent: symlinks intact after re-run"

echo "TEST: install.sh warns when openai/codex-plugin-cc is missing"
# Fake home has no plugins/ dir, so the official plugin is 'missing'.
output="$(run_with_home "$FAKE_HOME" install.sh 2>&1)"
if ! echo "$output" | grep -qi "codex-plugin-cc"; then
  fail "expected warning about missing openai/codex-plugin-cc"
fi
pass "warning printed when upstream plugin is missing"

echo "TEST: install.sh is silent about upstream when codex-plugin-cc is present"
mkdir -p "$FAKE_HOME/.claude/plugins/cache/openai/codex-plugin-cc"
output="$(run_with_home "$FAKE_HOME" install.sh 2>&1)"
if echo "$output" | grep -qi "missing.*codex-plugin-cc"; then
  fail "should not warn when upstream plugin is detected"
fi
pass "no false warning when upstream is present"

echo "ALL INSTALL TESTS PASSED"
```

- [ ] **Step 2.2: Run the test, verify it fails (no install.sh yet)**

```bash
cd /Users/glebstarcikov/codex-check
chmod +x tests/install.test.sh
bash tests/install.test.sh
```

Expected: FAIL with something like `bash: /Users/glebstarcikov/codex-check/install.sh: No such file or directory` and `install.sh exited non-zero`.

- [ ] **Step 2.3: Write minimal `install.sh` to pass the symlink-creation test**

```bash
#!/usr/bin/env bash
# install.sh — symlinks codex-check skill + commands into ~/.claude/.
# Idempotent: re-running replaces existing symlinks at the same paths.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
COMMANDS_DIR="$CLAUDE_DIR/commands"

mkdir -p "$SKILLS_DIR" "$COMMANDS_DIR"

# Replace-or-create symlink: removes any existing file/symlink at the target path first.
link() {
  local src="$1"
  local dst="$2"
  if [[ -e "$dst" || -L "$dst" ]]; then
    rm -f "$dst"
  fi
  ln -s "$src" "$dst"
  echo "  ✓ linked $dst → $src"
}

echo "Installing codex-check…"
link "$REPO_ROOT/skills/codex-check"      "$SKILLS_DIR/codex-check"
link "$REPO_ROOT/commands/codex-check.md" "$COMMANDS_DIR/codex-check.md"
link "$REPO_ROOT/commands/codex-check-setup.md" "$COMMANDS_DIR/codex-check-setup.md"

# Detect whether openai/codex-plugin-cc is installed and warn if not.
# Plugin caches live under ~/.claude/plugins/cache/<owner>/<repo>/.
UPSTREAM_GLOB="$CLAUDE_DIR/plugins/cache/openai/codex-plugin-cc"
if [[ ! -e "$UPSTREAM_GLOB" ]]; then
  echo
  echo "⚠️  openai/codex-plugin-cc not detected at $UPSTREAM_GLOB"
  echo "    codex-check is a wrapper on top of it. Install upstream first:"
  echo "      /plugin marketplace add openai/codex-plugin-cc"
  echo "      /plugin install codex@openai-codex"
  echo "      /codex:setup"
fi

echo
echo "✅ codex-check installed."
```

- [ ] **Step 2.4: Make install.sh executable and re-run tests**

```bash
cd /Users/glebstarcikov/codex-check
chmod +x install.sh
bash tests/install.test.sh
```

Expected output: four `✓` lines and `ALL INSTALL TESTS PASSED`.

- [ ] **Step 2.5: Run shellcheck on install.sh**

```bash
# If shellcheck isn't installed: brew install shellcheck (macOS) or skip with a note.
command -v shellcheck >/dev/null && shellcheck install.sh tests/install.test.sh tests/lib.sh
```

Expected: silent (no findings) or only style-level info (no errors/warnings). Fix any reported error before commit.

- [ ] **Step 2.6: Commit**

```bash
cd /Users/glebstarcikov/codex-check
git add install.sh tests/install.test.sh
# Tests dir's .gitkeep can come out now if it was added.
[[ -f tests/.gitkeep ]] && git rm tests/.gitkeep
git commit -m "feat(install): add idempotent install.sh + tests

Symlinks skills/codex-check and commands/codex-check{,-setup}.md into
~/.claude/. Idempotent: re-running replaces existing symlinks at same
paths. Detects openai/codex-plugin-cc upstream and warns if missing."
git push
```

---

## Task 3: uninstall.sh — TDD

**Files:**
- Create: `tests/uninstall.test.sh`
- Create: `uninstall.sh`

Mirror Task 2 for the inverse operation.

- [ ] **Step 3.1: Write `tests/uninstall.test.sh`**

```bash
#!/usr/bin/env bash
# tests/uninstall.test.sh — verify uninstall.sh removes our three symlinks
# and is idempotent (running on a clean install is a no-op, exit 0).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

echo "TEST: uninstall.sh removes all three symlinks"
FAKE_HOME="$(make_fake_home)"
trap 'rm -rf "$FAKE_HOME"' EXIT

run_with_home "$FAKE_HOME" install.sh > /dev/null 2>&1
run_with_home "$FAKE_HOME" uninstall.sh > /tmp/uninstall-test.out 2>&1 || {
  cat /tmp/uninstall-test.out
  fail "uninstall.sh exited non-zero"
}

assert_absent "$FAKE_HOME/.claude/skills/codex-check"
assert_absent "$FAKE_HOME/.claude/commands/codex-check.md"
assert_absent "$FAKE_HOME/.claude/commands/codex-check-setup.md"
pass "all three symlinks removed"

echo "TEST: uninstall.sh is idempotent on a clean state"
run_with_home "$FAKE_HOME" uninstall.sh > /tmp/uninstall-test.out 2>&1 || {
  cat /tmp/uninstall-test.out
  fail "uninstall.sh on already-clean state should exit 0"
}
pass "idempotent: clean state still exits 0"

echo "TEST: uninstall.sh does not touch unrelated files in ~/.claude/skills"
mkdir -p "$FAKE_HOME/.claude/skills/some-other-skill"
echo "hello" > "$FAKE_HOME/.claude/skills/some-other-skill/SKILL.md"
run_with_home "$FAKE_HOME" install.sh > /dev/null 2>&1
run_with_home "$FAKE_HOME" uninstall.sh > /dev/null 2>&1
[[ -f "$FAKE_HOME/.claude/skills/some-other-skill/SKILL.md" ]] || \
  fail "uninstall.sh wiped an unrelated skill"
pass "unrelated skills untouched"

echo "ALL UNINSTALL TESTS PASSED"
```

- [ ] **Step 3.2: Run, verify it fails (no uninstall.sh yet)**

```bash
cd /Users/glebstarcikov/codex-check && chmod +x tests/uninstall.test.sh && bash tests/uninstall.test.sh
```

Expected: FAIL with `No such file or directory: uninstall.sh`.

- [ ] **Step 3.3: Write `uninstall.sh`**

```bash
#!/usr/bin/env bash
# uninstall.sh — removes the three symlinks created by install.sh.
# Does not touch unrelated files. Idempotent: clean state exits 0.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"

# Only remove symlinks we own. Never `rm -rf` a directory.
unlink_if_ours() {
  local path="$1"
  if [[ -L "$path" ]]; then
    rm -f "$path"
    echo "  ✓ removed $path"
  elif [[ -e "$path" ]]; then
    echo "  ⚠️  $path exists but is not a symlink — leaving it alone." >&2
  fi
}

echo "Uninstalling codex-check…"
unlink_if_ours "$CLAUDE_DIR/skills/codex-check"
unlink_if_ours "$CLAUDE_DIR/commands/codex-check.md"
unlink_if_ours "$CLAUDE_DIR/commands/codex-check-setup.md"

echo "✅ codex-check uninstalled."
```

- [ ] **Step 3.4: Make executable, run tests**

```bash
cd /Users/glebstarcikov/codex-check && chmod +x uninstall.sh && bash tests/uninstall.test.sh
```

Expected: three `✓` lines and `ALL UNINSTALL TESTS PASSED`.

- [ ] **Step 3.5: Re-run install tests to make sure nothing regressed**

```bash
bash tests/install.test.sh
```

Expected: `ALL INSTALL TESTS PASSED`.

- [ ] **Step 3.6: shellcheck**

```bash
command -v shellcheck >/dev/null && shellcheck uninstall.sh tests/uninstall.test.sh
```

Expected: clean. Fix any errors/warnings.

- [ ] **Step 3.7: Commit**

```bash
git add uninstall.sh tests/uninstall.test.sh
git commit -m "feat(install): add uninstall.sh + tests

Removes only the symlinks created by install.sh; never touches unrelated
files in ~/.claude/. Idempotent: running on a clean state exits 0 with
no changes."
git push
```

---

## Task 4: skills/codex-check/SKILL.md

**Files:**
- Create: `skills/codex-check/SKILL.md`

The auto-trigger + flow document. Per spec §4.1.

- [ ] **Step 4.1: Create the directory and file**

```bash
mkdir -p /Users/glebstarcikov/codex-check/skills/codex-check
```

Write `skills/codex-check/SKILL.md`:

```markdown
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
```

- [ ] **Step 4.2: Validate YAML frontmatter parses**

```bash
cd /Users/glebstarcikov/codex-check
# Quick parser check using a tiny python one-liner (Python is on every macOS install).
python3 -c "
import yaml, sys
text = open('skills/codex-check/SKILL.md').read()
parts = text.split('---', 2)
if len(parts) < 3:
    sys.exit('frontmatter delimiters missing')
meta = yaml.safe_load(parts[1])
assert 'name' in meta and 'description' in meta, 'missing required fields'
print('frontmatter OK:', list(meta.keys()))
"
```

Expected: `frontmatter OK: ['name', 'description']`.

- [ ] **Step 4.3: Commit**

```bash
git add skills/codex-check/SKILL.md
git commit -m "feat(skill): add codex-check SKILL.md

Auto-trigger description matching high-risk surfaces (generic + project
CLAUDE.md ## Codex Check Triggers section) plus body covering intent
assembly, focus-text construction, /codex:adversarial-review invocation,
severity-grouped triage, anti-recursion, and subagent-mode guidance."
git push
```

---

## Task 5: commands/codex-check.md

**Files:**
- Create: `commands/codex-check.md`

Slash command that fires the SKILL.md flow with optional pass-through args. Per spec §4.2.

- [ ] **Step 5.1: Create the file**

```bash
mkdir -p /Users/glebstarcikov/codex-check/commands
```

Write `commands/codex-check.md`:

```markdown
---
description: Run a 3-axis Codex review (bugs / intent / invariant fit) on the current diff via openai/codex-plugin-cc
allowed-tools: Bash, Read, Edit
---

Execute the codex-check flow defined in the codex-check skill:

1. Read the project's CLAUDE.md (if present) and extract its `## Codex Check Triggers` section.
2. Summarize the user's stated intent for this session in 1–3 sentences.
3. Build the focus text covering three review axes (BUGS / INTENT MATCH / INVARIANT FIT) per the skill instructions.
4. Pass user-provided arguments through:
   - If the invocation includes `--base <ref>`, forward it to `/codex:adversarial-review --base <ref>`.
   - If the invocation includes `--background`, forward it.
   - Any remaining free-text after the flags is appended to the focus text *after* the 3 default axes.
5. Invoke `/codex:adversarial-review <flags> <focus text>`.
6. Triage the returned findings by severity and surface a summary per the skill's triage rules.

If `/codex:adversarial-review` fails because `openai/codex-plugin-cc` is not installed, surface the error verbatim and direct the user to:

```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/codex:setup
```

Do not try to install or repair codex yourself.
```

- [ ] **Step 5.2: Validate frontmatter**

```bash
python3 -c "
import yaml
text = open('/Users/glebstarcikov/codex-check/commands/codex-check.md').read()
parts = text.split('---', 2)
meta = yaml.safe_load(parts[1])
assert 'description' in meta
print('OK:', list(meta.keys()))
"
```

Expected: `OK: ['description', 'allowed-tools']`.

- [ ] **Step 5.3: Commit**

```bash
git add commands/codex-check.md
git commit -m "feat(command): add /codex-check slash command

Thin wrapper over /codex:adversarial-review. Reads project CLAUDE.md
triggers section, summarizes intent, constructs 3-axis focus text,
forwards --base/--background flags, triages output by severity."
git push
```

---

## Task 6: commands/codex-check-setup.md

**Files:**
- Create: `commands/codex-check-setup.md`

Per-project setup command. Drafts the `## Codex Check Triggers` section into the project's CLAUDE.md based on codebase analysis. Per spec §4.3.

- [ ] **Step 6.1: Write the file**

```markdown
---
description: Analyze the current repo and propose a "## Codex Check Triggers" section for its CLAUDE.md
allowed-tools: Bash, Read, Edit, Write, Glob, Grep
---

Per-project setup for codex-check. Run once per repository to populate the trigger surfaces that codex-check should auto-fire on.

## Step 1: Locate repo root

```bash
git rev-parse --show-toplevel
```

If this fails, ask the user to run the command from inside a git repository.

## Step 2: Gather signal

Read the following (each is best-effort — file might not exist):

- `CLAUDE.md` at repo root — existing conventions, invariants, "must not regress" language
- `README.md` at repo root — project description, stack
- Top-level directory structure (`ls -la` output, focusing on `db/`, `auth/`, `server/`, `api/`, `migrations/`, etc.)
- `package.json` (or `pyproject.toml` / `Cargo.toml` / `go.mod`) — dependencies that hint at high-risk areas
- Recent commit subjects: `git log --oneline -20`

## Step 3: Identify high-risk surfaces

Look for files/directories matching:

- **Database / persistence:** `db/`, `migrations/`, `prisma/`, `schema.{ts,sql,py,rb}`, ORM tenant primitives
- **Auth / sessions:** `auth/`, `session/`, anything with password hashing, OAuth flows, JWT signing
- **Realtime / streaming:** WebSocket handlers, SSE endpoints, message brokers
- **Webhooks / payments:** webhook handlers, Stripe/payment integration
- **Env / secrets:** `env.{ts,py}`, `config/`, secret loaders
- **Security-sensitive code:** CSRF, CORS, sanitization, encryption helpers
- **Infrastructure:** Dockerfile, deploy scripts, fly.toml, vercel.json, k8s manifests if they affect runtime
- **Anything CLAUDE.md explicitly flags:** existing CLAUDE.md sections labelled "invariant," "must not regress," "load-bearing," "do not regress"

## Step 4: Draft the triggers section

Construct a `## Codex Check Triggers` markdown section. For each surface, give a file path or glob and a one-line rationale (the *why*, not the *what*). Example:

```markdown
## Codex Check Triggers

Fire `/codex-check` (or auto-invoke via the codex-check skill) before
reporting completion when the diff touches any of:

- `db/schema.ts`, `db/migrations/` — schema or migration changes can break tenant isolation silently
- `db/tenant.ts`, files importing `tenantDb`/`adminDb` — invariant: app code must not bypass the tenant primitive
- `server/routes/_ws.ts` — websocket lifecycle; race conditions cause silent session drops
- `server/utils/auth/*` — auth changes have the largest blast radius

**Why these surfaces:** <one-paragraph rationale tying back to the project's specific risks>.
```

The rationale paragraph is important — it explains why this list, not just what's on it.

## Step 5: Show + approve

Show the proposed section to the user. Ask whether to:

1. Write it as-is to CLAUDE.md
2. Edit before writing (let the user dictate changes)
3. Skip — they'll write it manually later

If the user approves, append the section to existing CLAUDE.md (or create the file with just this section if it doesn't exist).

## Step 6: Idempotency

If `## Codex Check Triggers` already exists in CLAUDE.md, do **not** overwrite. Instead:

1. Read the existing section
2. Compare with what you would have proposed
3. Show the diff to the user
4. Ask whether to merge / replace / skip

Running the command twice with no codebase changes should produce no diff and exit cleanly.

## Step 7: Confirm

Print one line confirming what was done: "Wrote `## Codex Check Triggers` section to CLAUDE.md (8 surfaces)." or "No changes — section already present and current."
```

- [ ] **Step 6.2: Validate frontmatter**

```bash
python3 -c "
import yaml
text = open('/Users/glebstarcikov/codex-check/commands/codex-check-setup.md').read()
parts = text.split('---', 2)
meta = yaml.safe_load(parts[1])
assert 'description' in meta
print('OK:', list(meta.keys()))
"
```

- [ ] **Step 6.3: Commit**

```bash
git add commands/codex-check-setup.md
git commit -m "feat(command): add /codex-check-setup for per-project triggers

Analyzes the current repo and drafts a '## Codex Check Triggers' section
to append to CLAUDE.md. Idempotent: existing sections trigger a diff/
merge prompt instead of an overwrite. Includes rationale paragraph so
future maintainers know why each surface is on the list."
git push
```

---

## Task 7: Full README.md

**Files:**
- Modify: `README.md` (currently a stub)

Replace the design-phase stub with the v1 user-facing README per spec §4.5.

- [ ] **Step 7.1: Replace `README.md` with the full v1 content**

```markdown
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
```

- [ ] **Step 7.2: Commit**

```bash
git add README.md
git commit -m "docs(readme): full v1 README

Replaces design-phase stub. Covers prerequisites, two-step install,
per-project /codex-check-setup, usage examples, compatibility with
superpowers skills, limitations, uninstall."
git push
```

---

## Task 8: End-to-end test in a clean clone

**Files:** none modified — verification only.

Verify a fresh clone of the repo installs cleanly and the symlinks resolve correctly.

- [ ] **Step 8.1: Clone into a tempdir and run install**

```bash
TMP="$(mktemp -d -t codex-check-e2e.XXXXXX)"
cd "$TMP"
git clone https://github.com/glebstarchikov/codex-check.git
cd codex-check
FAKE_HOME="$(mktemp -d -t codex-check-fake-home.XXXXXX)"
HOME="$FAKE_HOME" ./install.sh
echo "--- skill ---"
readlink "$FAKE_HOME/.claude/skills/codex-check"
echo "--- commands ---"
readlink "$FAKE_HOME/.claude/commands/codex-check.md"
readlink "$FAKE_HOME/.claude/commands/codex-check-setup.md"
echo "--- uninstall ---"
HOME="$FAKE_HOME" ./uninstall.sh
ls "$FAKE_HOME/.claude/skills/" 2>/dev/null
ls "$FAKE_HOME/.claude/commands/" 2>/dev/null
echo "--- cleanup ---"
rm -rf "$TMP" "$FAKE_HOME"
```

Expected:
- Three valid symlinks reported by `readlink`
- Empty output after `uninstall.sh` (or "No such file or directory" — both acceptable)

- [ ] **Step 8.2: Run the test suite from the cloned tree to confirm portability**

```bash
cd "$TMP/codex-check"
bash tests/install.test.sh
bash tests/uninstall.test.sh
```

Expected: `ALL INSTALL TESTS PASSED` and `ALL UNINSTALL TESTS PASSED`.

(No commit — this is a sanity-check task.)

---

## Task 9: Live smoke test in Guia

**Files:** modifies `~/Guia/CLAUDE.md` (with user approval).

Now that everything is built and pushed, install for real on the developer's machine and exercise both commands end-to-end against a real repo (Guia).

- [ ] **Step 9.1: Install for real**

```bash
cd /Users/glebstarcikov/codex-check
./install.sh
```

Expected: three `✓ linked` lines and `✅ codex-check installed.` Possibly the upstream-missing warning if `openai/codex-plugin-cc` isn't installed yet — note this for the next step.

- [ ] **Step 9.2: Install upstream plugin if missing**

In Claude Code (manual user step):

```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/codex:setup
```

`/codex:setup` will walk through `codex login` (uses ChatGPT Plus subscription).

- [ ] **Step 9.3: Run `/codex-check-setup` in Guia**

In Claude Code, in the Guia working directory:

```
/codex-check-setup
```

Expected: Claude proposes a `## Codex Check Triggers` section listing surfaces like `db/schema.ts`, `db/migrations/`, `db/tenant.ts`, `server/routes/_ws.ts`, `server/utils/gemini/*`, `server/utils/env.ts`. Each with a one-line rationale tied to Phase 3A invariants.

Approve and write to Guia's CLAUDE.md (this is the only Guia change in this plan).

- [ ] **Step 9.4: Make a small high-risk change and fire `/codex-check`**

Pick a low-stakes test edit in Guia that touches a trigger surface. Suggestion: a one-line comment edit in `db/tenant.ts` or `server/routes/_ws.ts`. Then in Claude Code:

```
/codex-check
```

Expected:
- Claude builds the focus text with the 3 axes plus the trigger surfaces from CLAUDE.md
- `/codex:adversarial-review` runs (~30–90s)
- Claude triages output: any BLOCKERs/CONCERNs/NITs surfaced; verdict line printed
- Claude pushes back on any false-positive findings rather than dutifully accepting

Revert the test edit afterwards (`git checkout -- <file>`).

- [ ] **Step 9.5: Commit Guia's CLAUDE.md addition (separate Guia commit, not codex-check repo)**

```bash
cd /Users/glebstarcikov/Guia
git add CLAUDE.md
git commit -m "docs(claude.md): add ## Codex Check Triggers section

Lists the high-risk surfaces in Guia (Phase 3A invariants, Gemini
upstream, env validation, WS lifecycle) so codex-check auto-fires on
diffs touching them. Drafted by /codex-check-setup."
```

(No push for Guia unless the user wants to.)

---

## Task 10: Repo polish

**Files:** GitHub repo metadata only.

- [ ] **Step 10.1: Add topics to the GitHub repo**

```bash
gh repo edit glebstarchikov/codex-check --add-topic claude-code --add-topic codex --add-topic plugin --add-topic ai-tools --add-topic code-review
```

- [ ] **Step 10.2: Tag v0.1.0**

```bash
cd /Users/glebstarcikov/codex-check
git tag -a v0.1.0 -m "v0.1.0 — initial release

- /codex-check slash command (3-axis review wrapper over /codex:adversarial-review)
- /codex-check-setup per-project triggers drafter
- codex-check skill with auto-trigger description + flow + subagent guidance
- install.sh / uninstall.sh with bash test harness
- Full README + design doc"
git push --tags
```

- [ ] **Step 10.3: Optional — create a v0.1.0 GitHub release**

```bash
gh release create v0.1.0 --title "v0.1.0 — initial release" --notes "Initial public release of codex-check.

See README and docs/design.md for the full picture. Quick install:

\`\`\`bash
git clone https://github.com/glebstarchikov/codex-check.git ~/codex-check
cd ~/codex-check && ./install.sh
\`\`\`

Requires \`openai/codex-plugin-cc\` installed first."
```

---

## Acceptance criteria (from spec §13)

- [x] Repo public on GitHub with MIT license, README covering all required sections.
- [ ] `install.sh` symlinks the skill + two commands into `~/.claude/`, idempotent, prints clear status. *(Task 2)*
- [ ] `uninstall.sh` removes them cleanly. *(Task 3)*
- [ ] `/codex-check` fires `/codex:adversarial-review` with the 3-axis focus text and triages output by severity. *(Task 5 + 9.4)*
- [ ] `/codex-check-setup` proposes a `## Codex Check Triggers` section for the current repo and writes it to CLAUDE.md after approval. *(Task 6 + 9.3)*
- [ ] SKILL.md description is generic enough to fire correctly in repos other than Guia. *(Task 4 — spec §7 trigger taxonomy is repo-agnostic)*
- [ ] Manual end-to-end test in Guia: `/codex-check-setup` produces a sensible Phase 3A trigger list; `/codex-check` returns a usable review on a non-trivial diff. *(Task 9)*
- [ ] Manual test in a second repo. *(Deferred — flagged in the issue tracker after v0.1.0 ships.)*
- [ ] README acknowledges `openai/codex-plugin-cc` upstream. *(Task 7)*
