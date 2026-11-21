# MacBar

Tiny macOS menu-bar app for a laggy dev Mac. One icon, three jobs:

- **Memory**: RAM, swap and free disk at a glance. Top memory apps, click to quit or force quit. Optional `purge`.
- **Claude sessions & MCP**: finds stale Claude sessions and orphaned MCP servers (argent, rea, chrome-devtools, openmotion, selenium, playwright, ...). Filter by age (all running, 1h, 3h, 6h, 12h, 24h) and stop them in one click. Optional dev servers (expo, vitest, vite).
- **Keep awake**: like Caffeine and Amphetamine in one. Keep the Mac awake for 15 min to 8 h, or indefinitely. Optional "keep screen on". A **lid closed** mode keeps it running with the lid shut (uses `pmset disablesleep`, asks for Touch ID or your admin password, reverts by itself when the timer ends).
- **Disk**: clears Xcode DerivedData, the npm cache and old Homebrew downloads.

Lid-closed mode: do not carry the Mac in a bag while it is on, it can overheat. If you quit MacBar with it on, you are asked whether to turn it off. Manual off: `sudo pmset -a disablesleep 0`.

Touch ID instead of a password: run `sudo sh -c 'sed "s/^#auth/auth/" /etc/pam.d/sudo_local.template > /etc/pam.d/sudo_local'` once (macOS 14+). MacBar then uses `sudo` with Touch ID and falls back to the password dialog.

No network code. No telemetry. Everything runs locally.

## Download

1. Download `MacBar.dmg` from the Releases page and open it.
2. Drag **MacBar** onto the **Applications** folder in the window.
3. Open MacBar from Applications (or Spotlight). The first time, right-click it and choose **Open**, because the app is ad-hoc signed.

Apple Silicon, macOS 13+. `MacBar.zip` has the same app if you prefer a zip.
It launches at login by default after the first run. Turn it off from the menu (**Launch at login**).

## Build from source

Needs Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh
```

`./release.sh` also writes `dist/MacBar.dmg` and `dist/MacBar.zip`. `tools/make-icon.sh` redraws the app icon.

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
