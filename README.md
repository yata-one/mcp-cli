# mcp-cli

A lightweight, MoonBit-based CLI for interacting with MCP (Model Context Protocol) servers.

## Features

- Lightweight
- Single Binary
- Shell-Friendly
- Agent-Optimized
- Universal
  - **stdio**
  - **Streamable HTTP** (`application/json` / `text/event-stream`)
- Connection Pooling
- Tool Filtering
- Server Instructions
- Actionable Errors
- JSONC Friendly (New)
- Agent Skill Friendly (New)

## Quick Start

### 1. Installation

via shell script:

```sh
```

via mise (github backend)

```sh
```

via nix

```nix
```

### 2. Create a config file

Create `mcp-cli.json`:

```jsonc
{
  "mcpServers": {
    "local": {
      // stdio
      "command": "npx",
      "args": ["-y", "mcp_server"],
      "env": { "API_KEY": "${API_KEY}" },
      "cwd": "/path/to/project",
      // tools filter (glob)
      "allowedTools": ["*"],
      "disabledTools": ["delete_*"]
    },
    "remote": {
      // Streamable HTTP
      "url": "https://mcp.example.com/mcp",
      "headers": { "Authorization": "Bearer ${TOKEN}" },
      "allowedTools": ["read_*"],
      "disabledTools": []
    }
  }
}
```

Set `mcp-cli.jsonc` in the following directories:

1. `$HOME/.agents/mcp-cli.json`
2. `$HOME/.agents/mcp-cli.jsonc`
3. `{project-root}/.agents/mcp-cli.json`
4. `{project-root}/.agents/mcp-cli.jsonc`
5. Assert config file using `--config` or `-c` option:

```sh
mcp-cli --config mcp-cli.json
```

note: `{project-root}` is the location found by tracing from `cwd` to the parent until `.git` is found, or if not found, the `cwd` at execution time.

### 3. Discover available tools

```sh
# List all servers and tools
mcp-cli
```

### 4. Know how to use server and tool

```sh
mcp-cli info <server>
mcp-cli info <server> <tool>
mcp-cli info <server>/<tool>
```

### 5. Call a tool

```sh
# View tool schema first
mcp-cli info <server> <tool>

# Call the tool
mcp-cli call <server> <tool> '{"path": "<path>"}'
```

### Notes

#### Exit code
- `0`: success
- `1`: client error (arguments/settings)
- `2`: server/tool error
- `3`: network/transport error

#### glob（`allowedTools` / `disabledTools` / `grep`）

- `*`: any length
- `?`: 1 character
- Case-insensitive for ASCII
- `disabledTools` takes **priority** (always disabled if matched)

#### Environment Variables

- `MCP_NO_DAEMON=1`: disable daemon (always direct connection)
- `MCP_DAEMON_TIMEOUT=N`: daemon idle timeout seconds (default: 60)
- `MCP_TIMEOUT=N`: timeout seconds for each operation (default: 1800)
- `MCP_CONCURRENCY=N`: number of concurrent servers (default: 5)
- `MCP_MAX_RETRIES=N`: number of retries (default: 3)
- `MCP_RETRY_DELAY=N`: retry delay ms (default: 1000)
- `MCP_DEBUG=1`: debug output (currently just a flag)
- `MCP_STRICT_ENV=0|false`: make envsubst non-strict

## Development

Prerequirements: Moonbit

Dev:
```bash
# Test
moon test --target native
# E2E Test (via shell script)
bash scripts/e2e.sh
# Typecheck & Lint
moon check
# Format
moon fmt
```

Build: 
```sh
# Build
moon build --target native --release cli
```

## Reference

- [philschmid/mcp-cli](https://github.com/philschmid/mcp-cli)

## License

MIT
　