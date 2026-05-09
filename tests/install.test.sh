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

echo "TEST: install.sh warns when codex CLI is missing"
# Fake home has no codex anywhere; minimal PATH (set by run_with_home) excludes it.
output="$(run_with_home "$FAKE_HOME" install.sh 2>&1)"
if ! echo "$output" | grep -qi "codex CLI not found"; then
  fail "expected 'codex CLI not found' warning"
fi
if ! echo "$output" | grep -q "npm install -g @openai/codex"; then
  fail "expected install hint with npm command"
fi
pass "warning + install hint printed when codex is missing"

echo "TEST: install.sh detects codex at \$HOME/.npm-global/bin (fallback path)"
mkdir -p "$FAKE_HOME/.npm-global/bin"
printf '#!/usr/bin/env bash\necho "fake-codex"\n' > "$FAKE_HOME/.npm-global/bin/codex"
chmod +x "$FAKE_HOME/.npm-global/bin/codex"
output="$(run_with_home "$FAKE_HOME" install.sh 2>&1)"
if echo "$output" | grep -qi "codex CLI not found"; then
  fail "should not warn when codex is at \$HOME/.npm-global/bin/codex"
fi
if ! echo "$output" | grep -q "codex CLI detected at $FAKE_HOME/.npm-global/bin/codex"; then
  fail "expected 'detected at <path>' confirmation"
fi
pass "detected fake codex via \$HOME/.npm-global/bin fallback"

echo "TEST: install.sh detects codex on PATH (highest priority)"
rm -f "$FAKE_HOME/.npm-global/bin/codex"
mkdir -p "$FAKE_HOME/bin"
printf '#!/usr/bin/env bash\necho "fake-codex-on-path"\n' > "$FAKE_HOME/bin/codex"
chmod +x "$FAKE_HOME/bin/codex"
# Run with HOME=$FAKE_HOME but augment PATH to include the fake bin dir.
output="$(HOME="$FAKE_HOME" PATH="$FAKE_HOME/bin:/usr/bin:/bin" bash "$REPO_ROOT/install.sh" 2>&1)"
if echo "$output" | grep -qi "codex CLI not found"; then
  fail "should not warn when codex is on PATH"
fi
if ! echo "$output" | grep -q "codex CLI detected at $FAKE_HOME/bin/codex"; then
  fail "expected detection to report path-resolved codex location"
fi
pass "detected fake codex on PATH (preferred over fallback)"

echo "ALL INSTALL TESTS PASSED"
