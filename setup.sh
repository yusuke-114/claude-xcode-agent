#!/bin/bash
# Xcode ACP agent one-step installer
#   1. Install node if missing (prefers brew)
#   2. Install claude if missing (prefers brew)
#   3. Install the ACP adapter into .runtime/ in this directory (not globally; delete the directory to uninstall)
#   4. Run an ACP initialize handshake to check that claude-acp.sh starts
#   5. Print the absolute path to put in Xcode's "Executable" field
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME="$DIR/.runtime"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
has() { command -v "$1" >/dev/null 2>&1; }
# Adapter package names: upstream has renamed it, so use the first one that exists on npm and isn't deprecated
# (old package names stopped updating and bundle an old Claude Code, so the model list gets stuck at e.g. Opus 4.1)
PACKAGES="@agentclientprotocol/claude-agent-acp @zed-industries/claude-agent-acp @zed-industries/claude-code-acp"

echo "==> Checking node"
if has node; then
  echo "    Installed: node $(node -v)"
elif has brew; then
  brew install node
else
  echo "❌ Neither node nor brew found. Install Node.js first: https://nodejs.org" && exit 1
fi

echo "==> Checking claude"
if has claude; then
  echo "    Installed: $(claude --version)"
elif has brew; then
  brew install --cask claude-code
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

echo "==> Installing the ACP adapter into $RUNTIME"
PKG=""
for p in $PACKAGES; do
  npm view "$p" version >/dev/null 2>&1 || continue
  if [ -n "$(npm view "$p" deprecated 2>/dev/null)" ]; then
    echo "    Skipping deprecated $p"; continue
  fi
  PKG="$p"; break
done
[ -n "$PKG" ] || { echo "❌ No adapter found on npm ($PACKAGES). Check your network / npm registry"; exit 1; }
mkdir -p "$RUNTIME"
# Remove the previously installed adapter so old and new package names never coexist (logs and the debug switch are kept)
rm -rf "$RUNTIME/node_modules" "$RUNTIME/package.json" "$RUNTIME/package-lock.json"
npm install --prefix "$RUNTIME" --no-fund --no-audit "$PKG@latest"
BIN="$(ls "$RUNTIME"/node_modules/.bin/ | grep -E '^claude-.*acp$' | head -1)"
[ -n "$BIN" ] || { echo "❌ Installed $PKG but found no executable"; exit 1; }
# Saved for claude-acp.sh: node is not on PATH when Xcode launches it
{
  echo "ACP_BIN=\"$RUNTIME/node_modules/.bin/$BIN\""
  echo "NODE_DIR=\"$(dirname "$(command -v node)")\""
  echo "CLAUDE_BIN=\"$(command -v claude)\""
} > "$RUNTIME/paths.sh"
echo "    $PKG -> $BIN"

echo "==> Handshake test"
chmod +x "$DIR/claude-acp.sh"
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}'
OUT="$( (echo "$INIT"; sleep 5) | perl -e 'alarm 30; exec @ARGV' "$DIR/claude-acp.sh" 2>"$RUNTIME/handshake.err" | head -1 || true)"
if echo "$OUT" | grep -q '"protocolVersion"'; then
  echo "    ✅ Adapter responded"
else
  echo "    ⚠️  No initialize response. Error output:"
  sed 's/^/      /' "$RUNTIME/handshake.err" | tail -20
fi

echo
echo "✅ Done. In Xcode › Settings › Intelligence › Add an Agent…, enter:"
echo "   Name        : Claude"
echo "   Executable  : $DIR/claude-acp.sh"
echo "   Interpreter : (leave empty)"
if [ -f "$DIR/config.json" ]; then
  echo "ℹ️  Using config: $DIR/config.json (~/.claude/settings.json is not read by default)"
else
  echo "ℹ️  No config.json, so claude's existing login will be used. To use a custom gateway or API key:"
  echo "   cp $DIR/config.example.json $DIR/config.json && chmod 600 $DIR/config.json"
fi
echo "   If you move this directory, run ./setup.sh again"
