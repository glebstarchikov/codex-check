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
