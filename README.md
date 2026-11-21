# MacBar

Tiny macOS menu-bar app for a laggy dev Mac. One icon, three jobs:

- **Memory**: RAM, swap and free disk at a glance. Top memory apps, click to quit or force quit. Optional `purge`.
- **Claude sessions & MCP**: finds stale Claude sessions and orphaned MCP servers (argent, rea, chrome-devtools, openmotion, selenium, playwright, ...). Filter by age (all running, 1h, 3h, 6h, 12h, 24h) and stop them in one click. Optional dev servers (expo, vitest, vite).
- **Disk**: clears Xcode DerivedData, the npm cache and old Homebrew downloads.

No network code. No telemetry. Everything runs locally.

## Install

Needs Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh
```

Builds `~/Applications/MacBar.app`, launches it, and installs the CLI to `~/.local/bin/mcpclean`.

## CLI

```sh
mcpclean            # dry run, list what would be stopped
mcpclean --kill     # stop it
mcpclean --dev      # also include expo / vitest / vite
MAX_AGE_H=6 mcpclean
```

The CLI never touches the Claude session it is run from. The menu-bar app cannot tell which session is yours, so "All running sessions" asks for confirmation first.

## Add an MCP server to the list

Edit `mcp_re` in `bin/mcpclean`, then `./build.sh`.
