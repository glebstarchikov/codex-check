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
