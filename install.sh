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

# Detect the `codex` CLI binary. codex-check calls codex directly via Bash;
# it does NOT depend on the openai/codex-plugin-cc Claude Code plugin (though
# that plugin's slash commands can still be used alongside).
#
# Search order:
#   1. PATH (ideal — covers npm-global, Homebrew, plugin-bundled, custom installs)
#   2. Common install dirs that frequently aren't on a non-interactive shell's PATH
#      (Bash tool sessions in particular tend to miss .zshenv / .bashrc paths)
find_codex() {
  if command -v codex >/dev/null 2>&1; then
    command -v codex
    return 0
  fi
  local candidate
  for candidate in \
    "$HOME/.npm-global/bin/codex" \
    "$HOME/.bun/bin/codex" \
    "$HOME/.local/bin/codex" \
    "/opt/homebrew/bin/codex" \
    "/usr/local/bin/codex"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

if CODEX_BIN="$(find_codex)"; then
  echo
  echo "  ✓ codex CLI detected at $CODEX_BIN"
else
  echo
  echo "⚠️  codex CLI not found on PATH or in standard install locations."
  echo "    codex-check requires the OpenAI Codex CLI:"
  echo "      npm install -g @openai/codex"
  echo "      codex login    # OAuth via ChatGPT account, or set OPENAI_API_KEY"
fi

echo
echo "✅ codex-check installed."
