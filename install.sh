#!/bin/sh
# Installs claude-sessions for Rex.
#
#   curl -fsSL https://raw.githubusercontent.com/lassejlv/rex-claude-sessions/main/install.sh | sh
#
# Copies the plugin to <rex config dir>/plugins/claude-sessions/init.lua and adds
# a block to init.lua that loads it. Running it again updates the plugin and
# leaves the block, and any options you added to it, as they are.
set -eu

URL="https://raw.githubusercontent.com/lassejlv/rex-claude-sessions/main/init.lua"
CONFIG="${REX_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/rex/init.lua}"
PLUGIN_DIR="$(dirname "$CONFIG")/plugins/claude-sessions"
PLUGIN="$PLUGIN_DIR/init.lua"
BEGIN="-- >>> claude-sessions >>>"

say() { printf '%s\n' "$*"; }

mkdir -p "$PLUGIN_DIR"
tmp="$(mktemp "$PLUGIN_DIR/.init.lua.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# Run from a clone, use its copy; piped from curl, download it.
here="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
case "$0" in
  *install.sh) local_copy="$here/init.lua" ;;
  *) local_copy="" ;;
esac
if [ -n "$local_copy" ] && [ -f "$local_copy" ]; then
  cp "$local_copy" "$tmp"
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "$URL" -o "$tmp"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$tmp" "$URL"
else
  say "claude-sessions: needs curl or wget to download the plugin." >&2
  exit 1
fi
mv "$tmp" "$PLUGIN"
trap - EXIT
say "Installed the plugin at $PLUGIN"

if [ -f "$CONFIG" ] && grep -qF -e "$BEGIN" "$CONFIG"; then
  say "$CONFIG already loads it."
else
  [ -s "$CONFIG" ] && printf '\n' >> "$CONFIG"
  cat >> "$CONFIG" <<EOF
$BEGIN
-- "Recent Claude Sessions…" (shift+cmd+r): resume a Claude Code session in a new tab.
-- Options: https://github.com/lassejlv/rex-claude-sessions#configuration
dofile("$PLUGIN").setup()
-- <<< claude-sessions <<<
EOF
  say "Added a block that loads it to $CONFIG"
fi

if command -v rex >/dev/null 2>&1; then
  if rex config check "$CONFIG" >/dev/null && rex config reload >/dev/null 2>&1; then
    say "Reloaded Rex. Press Shift+Cmd+R, or search \"Recent Claude Sessions\" in the command palette."
  else
    say "Rex didn't reload. Run: rex config check && rex config reload" >&2
  fi
else
  say "Run \"rex config reload\" on the machine running the Rex server to load it."
fi
