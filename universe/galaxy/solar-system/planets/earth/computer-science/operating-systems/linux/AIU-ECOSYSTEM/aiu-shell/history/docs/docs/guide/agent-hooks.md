# AI Agent Hooks

aiu-shell-history can capture commands run by AI coding agents (like Claude Code, Codex, and pi) alongside your regular shell history. Each command is tagged with the agent that ran it, so you can filter your history by author.

## Quick Start

Install hooks for your agent, then restart or reload the agent:

```shell
# Claude Code
aiu-shell-history hook install claude-code

# Codex
aiu-shell-history hook install codex

# pi
aiu-shell-history hook install pi
```

That's it. Commands the agent runs will now appear in your aiu-shell-history history, tagged with the agent's name.

## How It Works

AI coding agents support hook systems that notify external tools when they're about to run a shell command and when the command finishes. aiu-shell-history uses these hooks to record each command as a history entry, just like commands you type yourself.

When `aiu-shell-history hook install` runs, it writes the agent's config file or extension to register aiu-shell-history as a hook handler:

| Agent | Config file / extension |
|-------|-------------------------|
| Claude Code | `~/.claude/settings.json` |
| Codex | `~/.codex/hooks.json` |
| pi | `~/.pi/agent/extensions/aiu-shell-history.ts` |

The hook lifecycle:

1. **PreToolUse** -- the agent is about to run a Bash command. aiu-shell-history records the command, working directory, and timestamp (same as `history start`).
2. **PostToolUse / PostToolUseFailure** -- the command finished. aiu-shell-history records the exit code and duration (same as `history end`).

Only `Bash` tool invocations are captured. Other tool types (file writes, web fetches, etc.) are ignored.

## Filtering by Author

By default, aiu-shell-history's interactive search shows only your own commands. Agent-run commands are hidden so they don't clutter your history.

Today this default is built into the search UI rather than configurable via `config.toml`. Interactive search uses the equivalent of:

- `$all-user` — any author that is **not** a known AI agent

For explicit author filtering, use the CLI `aiu-shell-history search --author ...` flag. Special values:

| Value | Meaning |
|-------|---------|
| `$all-user` | Any author that is **not** a known AI agent |
| `$all-agent` | Any known AI agent author |

You can also use literal author names:

```shell
# Show only your own commands and Claude Code commands
aiu-shell-history search --author '$all-user' --author 'claude-code' -- ''
```

```shell
# Show everything (no filtering)
aiu-shell-history search -- ''
```

```shell
# Show only agent commands
aiu-shell-history search --author '$all-agent' -- ''
```

Currently recognized agent names are: `claude-code`, `codex`, `copilot`, `opencode`, and `pi`.

## Supported Agents

### Claude Code

```shell
aiu-shell-history hook install claude-code
```

This adds hook entries to `~/.claude/settings.json`. Claude Code calls `aiu-shell-history hook claude-code` on each `Bash` tool use, passing the event as JSON on stdin.

### Codex

```shell
aiu-shell-history hook install codex
```

This adds hook entries to `~/.codex/hooks.json`. Codex calls `aiu-shell-history hook codex` on each Bash tool use matching `^Bash$`.

### pi

```shell
aiu-shell-history hook install pi
```

This writes aiu-shell-history's extension to `~/.pi/agent/extensions/aiu-shell-history.ts`.

Then restart pi or run `/reload`. The extension listens to pi's tool events and records every `bash` tool command with author `pi` by calling `aiu-shell-history history start` before execution and `aiu-shell-history history end` afterwards. Because it observes events rather than registering its own `bash` tool, it works alongside other extensions that replace pi's bash tool (such as sandboxes or RTK implementations).

## Verifying Installation

After installing hooks and restarting your agent, run a command through the agent and then check your history:

```shell
# Show all history including agent commands
aiu-shell-history search --author '' -- ''

# Show only agent commands
aiu-shell-history search --author '$all-agent' -- ''
```

You can also check the agent's config file directly to confirm the hooks are registered:

```shell
# Claude Code
cat ~/.claude/settings.json | grep aiu-shell-history

# Codex
cat ~/.codex/hooks.json | grep aiu-shell-history

# pi
ls ~/.pi/agent/extensions/aiu-shell-history.ts
```

## Re-installing

Running `aiu-shell-history hook install` again is safe. If hooks are already installed, the command will skip them and print a message:

```
hooks.PreToolUse: already installed, skipping
hooks.PostToolUse: already installed, skipping
hooks.PostToolUseFailure: already installed, skipping
```

For pi, reinstalling will also skip if the managed extension already matches the bundled version.
