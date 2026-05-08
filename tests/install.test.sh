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
