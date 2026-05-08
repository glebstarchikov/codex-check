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
