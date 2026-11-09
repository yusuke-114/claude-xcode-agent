#!/bin/zsh
# Xcode ACP agent entry point: put this file's absolute path in Xcode's "Executable" field, leave Interpreter empty
#   - Config is read only from config.json next to this script. Fields: base_url / auth_token / api_key / model / setting_sources / mcp_servers / env
#     effort / permission_mode / allowed_tools are controlled by Xcode and ignored here; without a config file, claude's existing login is used
#   - Defaults to --setting-sources project,local, so ~/.claude/settings.json is not read:
#     the adapter hardcodes setting-sources to user,project,local, so CLAUDE_CODE_EXECUTABLE makes it call this script instead,
#     and this script (with CLAUDE_ACP_AS_CLI=1) replaces that flag, adds mcp_servers, then runs the real claude
#   - stdout is the ACP protocol channel; this script must never print to stdout (all messages go to stderr)
DIR="${0:A:h}"
RUNTIME="$DIR/.runtime"
LOG="$RUNTIME/agent.log"

# ---------- Mode 2: called by the adapter as claude ----------
if [ "$CLAUDE_ACP_AS_CLI" = 1 ]; then
  args=() skip=0 mcp_added=0
  for a in "$@"; do
    if (( skip )); then skip=0; continue; fi
    case "$a" in
      --setting-sources) skip=1; continue ;;
      --setting-sources=*) continue ;;
    esac
    args+=("$a")
    # --mcp-config takes multiple values: if the adapter already passed one (Xcode's MCP), append ours so both are kept
    if [ "$a" = --mcp-config ] && [ -n "$CLAUDE_ACP_MCP_CONFIG" ]; then
      args+=("$CLAUDE_ACP_MCP_CONFIG"); mcp_added=1
    fi
  done
  if [ -n "$CLAUDE_ACP_MCP_CONFIG" ] && (( ! mcp_added )); then
    args+=(--mcp-config "$CLAUDE_ACP_MCP_CONFIG")
  fi
  echo "$(date '+%T') claude --setting-sources $CLAUDE_ACP_SETTING_SOURCES · mcp ${CLAUDE_ACP_MCP_NAMES:-(none)}" >>"$LOG"
  exec "$CLAUDE_ACP_REAL_CLAUDE" "${args[@]}" --setting-sources "$CLAUDE_ACP_SETTING_SOURCES"
fi

# ---------- Mode 1: launched by Xcode ----------
[ -f "$RUNTIME/paths.sh" ] || { echo "claude-acp: not installed, run $DIR/setup.sh first" >&2; exit 1; }
source "$RUNTIME/paths.sh"
# Xcode is launched from the GUI and doesn't read ~/.zshrc, so add PATH entries here
export PATH="$NODE_DIR:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

CONFIG="$DIR/config.json"
[ -f "$CONFIG" ] && CONFIG="${CONFIG:A}" || CONFIG=""
SETTING_SOURCES="project,local"
if [ -n "$CONFIG" ]; then
  # Turn the config into env vars for this process only, using the same rules as cchat (https://github.com/yusuke-114/cchat)
  EXPORTS="$(/usr/bin/python3 - "$CONFIG" "$RUNTIME" <<'PY'
import json, os, re, shlex, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
env = {}
if cfg.get("base_url"):   env["ANTHROPIC_BASE_URL"] = cfg["base_url"]
if cfg.get("api_key"):    env["ANTHROPIC_API_KEY"] = cfg["api_key"]        # x-api-key
if cfg.get("auth_token"): env["ANTHROPIC_AUTH_TOKEN"] = cfg["auth_token"]  # Authorization: Bearer
if cfg.get("model"):      env["ANTHROPIC_MODEL"] = cfg["model"]            # default model in Xcode
env.update({k: str(v) for k, v in (cfg.get("env") or {}).items()})
for k, v in env.items():
    # The output is eval'd, so only plain variable names are allowed
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k):
        sys.exit(f"invalid env name: {k!r}")
    print(f"export {k}={shlex.quote(v)}")
print("SETTING_SOURCES=" + shlex.quote(cfg.get("setting_sources") or "project,local"))
# Local MCP servers come only from the config file (as in cchat), not ~/.claude.json
mcp = cfg.get("mcp_servers") or {}
if not isinstance(mcp, dict):
    sys.exit("mcp_servers must be an object")
if mcp:
    # Written to a 0600 file so any secrets in the MCP env don't show up in `ps`
    path = os.path.join(sys.argv[2], "mcp.json")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump({"mcpServers": mcp}, f)
    os.chmod(path, 0o600)
    print("export CLAUDE_ACP_MCP_CONFIG=" + shlex.quote(path))
    print("export CLAUDE_ACP_MCP_NAMES=" + shlex.quote(",".join(mcp)))
PY
)" || { echo "claude-acp: failed to read config $CONFIG" >&2; exit 1; }
  eval "$EXPORTS"
fi

REAL_CLAUDE="${CLAUDE_BIN:-$(command -v claude)}"
[ -x "$REAL_CLAUDE" ] || { echo "claude-acp: claude command not found, run $DIR/setup.sh first" >&2; exit 1; }
export CLAUDE_CODE_EXECUTABLE="${0:A}" CLAUDE_ACP_AS_CLI=1
export CLAUDE_ACP_REAL_CLAUDE="$REAL_CLAUDE" CLAUDE_ACP_SETTING_SOURCES="$SETTING_SOURCES"

# Adapter errors only go to Xcode and never show up in its UI, so they're logged to .runtime/agent.log
echo "===== $(date '+%F %T') pid $$ · config ${CONFIG:-(none, using claude login)} · setting-sources $SETTING_SOURCES · $REAL_CLAUDE $("$REAL_CLAUDE" --version 2>&1) · node $(node -v 2>&1)" >>"$LOG"
exec 2>>"$LOG"

# Debugging: after `touch .runtime/debug`, protocol messages between Xcode and the adapter are logged too
# (they contain your conversation, so delete them when you're done)
if [ -f "$RUNTIME/debug" ]; then
  tee -a "$RUNTIME/debug.in.log" | "$ACP_BIN" "$@" | tee -a "$RUNTIME/debug.out.log"
  exit $pipestatus[2]
fi
exec "$ACP_BIN" "$@"
