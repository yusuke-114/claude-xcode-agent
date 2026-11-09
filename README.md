# claude-xcode-agent

Use Claude Code as the coding agent in Xcode 26, powered by your own API key or gateway.

Xcode 26's Intelligence features can connect to external agents through ACP (Agent Client Protocol).
This tool wraps Claude Code as an ACP agent that Xcode can call directly, and:

- **Works with your own gateway**: `base_url` + `auth_token` / `api_key`. The official API and any Anthropic-compatible gateway both work
- **Leaves your global config alone**: `~/.claude/settings.json` is not read by default; config lives only in `config.json` in this directory
- **Brings your own MCP servers**: `mcp_servers` are merged with the MCP servers Xcode provides and passed to claude
- **Installs locally**: the ACP adapter goes into `.runtime/`, not a global location. Delete the directory to uninstall
- **Easy to debug**: logs go to `.runtime/agent.log`, and you can optionally record the protocol messages between Xcode and the adapter

Requirements: macOS with Xcode 26 or later. `setup.sh` installs Node.js and Claude Code if they're missing.

## Quick start

**Step 1. Clone and install**

    git clone https://github.com/yusuke-114/claude-xcode-agent.git
    cd claude-xcode-agent
    ./setup.sh

At the end, setup prints the absolute path of `claude-acp.sh`. You'll need it in step 3.

**Step 2. Create your config file** (skip this step if `claude` is already logged in and you want to use that login)

    cp config.example.json config.json
    chmod 600 config.json

Open `config.json` and fill in your values:

    {
      "base_url": "https://your-gateway.example.com",
      "auth_token": "your-api-key",
      "model": "claude-opus-5-5"
    }

- Calling the Anthropic API directly: delete `base_url` and `auth_token`, and set `"api_key": "your-api-key"`.
- Going through a gateway or proxy: set `base_url` (without `/v1/messages`) and `auth_token`.
- Fields you don't need can be deleted. See [Configuration](#configuration) for every field.

**Step 3. Add the agent in Xcode**

Open **Xcode › Settings › Intelligence › Add an Agent…** and enter:

| Field | Value |
|---|---|
| Name | Claude |
| Executable | The absolute path to `claude-acp.sh` printed by setup |
| Interpreter | Leave empty |

**Step 4. Use it**

Open the coding assistant in Xcode, pick **Claude**, and ask something about your project.
If nothing happens, see [Troubleshooting](#troubleshooting).

If you move this directory, run `./setup.sh` again and update the Executable path in Xcode.

## Configuration
The config file is optional. Without `config.json`, claude uses its existing login.

| Field | Purpose |
|---|---|
| base_url | Gateway URL, without `/v1/messages` |
| auth_token | Sent as `Authorization: Bearer` |
| api_key | Sent as `x-api-key` (use either this or auth_token) |
| model | Default model in Xcode |
| setting_sources | Which settings layers claude reads. The default is `project,local` (skips `~/.claude/settings.json`). Use `user,project,local` to read all of them |
| mcp_servers | Local MCP servers, passed to claude with `--mcp-config` (doesn't depend on `~/.claude.json`); see the example below |
| env | Extra environment variables, passed to claude unchanged |

Effort, permission mode and allowed tools are controlled by Xcode, so they aren't configured here.

Credentials are passed to claude as environment variables, and `mcp_servers` is written to
`.runtime/mcp.json` with mode 0600, so neither appears on the command line.

mcp_servers example (stdio):

    "mcp_servers": {
      "my-tool": { "command": "/absolute/path/to/server", "args": ["--stdio"], "env": {} }
    }

## How it works
The ACP adapter hardcodes `--setting-sources` to `user,project,local`. To change that,
`claude-acp.sh` sets `CLAUDE_CODE_EXECUTABLE` so the adapter calls the script back.
When called as claude (`CLAUDE_ACP_AS_CLI=1`), the script replaces that flag, appends `mcp_servers`,
and then runs the real claude.

    Xcode ──ACP──▶ claude-acp.sh ──▶ ACP adapter ──▶ claude-acp.sh (as claude) ──▶ claude

stdout is the ACP protocol channel, so all of the script's own messages go to stderr.

## Troubleshooting
- Logs: `.runtime/agent.log`. Adapter errors are only sent to Xcode and never shown in its UI, so they're written here.
- Protocol messages: after `touch .runtime/debug`, messages between Xcode and the adapter are written to `.runtime/debug.in.log` / `debug.out.log`.
  **They contain your conversation. Delete `debug` and both logs when you're done.**

## Uninstall
Delete `.runtime/` and remove the agent in Xcode.

## License
[MIT](LICENSE)
