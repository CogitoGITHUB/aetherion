# MCP Server

aiu-shell-history ships with a built-in [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) server, giving external AI tools like Claude Code and Cursor access to your shell history. Your agent can look up commands you've run before, check whether they succeeded, and — with [output capture](./command-output.md) set up — read what they printed.

The server exposes the same history tools that [aiu-shell-history AI](./introduction.md) uses. Both tools are read-only: nothing can modify or delete your history, and all data stays on your machine.

## Starting the server

The MCP server runs over stdio, so your MCP client starts it for you — there's nothing to keep running in the background. The command is simply:

```shell
aiu-shell-history mcp
```

### Claude Code

```shell
claude mcp add aiu-shell-history -- aiu-shell-history mcp
```

### Cursor, Claude Desktop, and other clients

Most MCP clients accept a JSON configuration like this:

```json
{
  "mcpServers": {
    "aiu-shell-history": {
      "command": "aiu-shell-history",
      "args": ["mcp"]
    }
  }
}
```

If the `aiu-shell-history` binary is not on your client's `PATH`, use the full path to the binary instead (e.g. `~/.aiu-shell-history/bin/aiu-shell-history`).

## Tools

### `aiu_shell_history_history`

Searches your shell history, using the same fuzzy matching as the search TUI. Each result includes the command, when and where it ran, its exit code, and its duration, along with a history ID that can be passed to `aiu_shell_history_output`.

Searches can be narrowed down in a few ways:

- **Filter mode**: the same scopes as [interactive search](../guide/advanced-usage.md) — `global`, `host`, `directory`, `workspace`, or `session`. The `directory` and `workspace` scopes are relative to the directory the server was launched in, which for most editors is your project directory.
- **Failed commands only**: return only commands that exited with a non-zero exit code.
- **Author**: filter to commands you ran yourself, commands run by AI agents, or commands run by one specific agent. See [AI Agent Hooks](../guide/agent-hooks.md) for how agent-run commands are recorded.

History search reads the aiu-shell-history database directly, so it works without any extra setup.

### `aiu_shell_history_output`

Fetches the captured terminal output of a previous command, identified by a history ID from `aiu_shell_history_history` results. The agent can fetch specific line ranges, so it doesn't need to read a huge log to find the error at the end.

Output capture requires the [daemon](../reference/daemon.md) and [pty-proxy](../reference/pty-proxy.md) to be running — see [Reading Command Output](./command-output.md) for setup. Without them, the tool responds with an error explaining that no output is available.

!!! note "Session scope"

    The `session` filter mode only works when the MCP server is launched from inside an aiu-shell-history-enabled shell session. Clients like editors usually launch it outside of one, in which case the other filter modes still work as normal.
