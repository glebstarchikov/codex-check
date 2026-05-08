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
