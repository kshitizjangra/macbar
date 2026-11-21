# MacBar: project context

A summary of what was built, why, how it works, and what is still open. Written so someone new can pick it up without the original chat.

- Repo: https://github.com/kshitizjangra/macbar (private)
- Latest release: v0.2.3
- Platform: macOS 13+, Apple Silicon. Swift (AppKit) + one bash script.

## 1. Why this exists

The Mac (M-series, 24 GB RAM, about 926 GB disk) was lagging badly. Diagnosis:

| Finding | Detail |
|---|---|
| CPU overloaded | Load average about 30 to 60 on 10 cores. A `vitest run` had 8 worker processes. |
| Memory exhausted | About 28.7 GB of swap in use, about 500k pageouts. |
| Process pile-up | 86 node processes. Eight Claude Code sessions in the Antigravity IDE had been open for 1 to 2 days, and each one starts its own set of MCP servers (argent, rea, chrome-devtools, openmotion, selenium, playwright, mcp-remote, MCP Magic), around 5 to 10 node processes per session. |
| Disk nearly full | 95% used, about 51 GB free. |

Cleanup done by hand: stopped the 8 stale sessions, their MCP servers, vitest and the Expo builds. Node processes went from 86 to 23 and swap use dropped from 28.7 GB to 25.5 GB. Load stayed high until swap drains, which only a restart fully fixes.

## 2. Alternatives considered

- **Nexus Console** (github.com/xDAnkit/Nexus-Console): a Tauri app for managing Homebrew services and ports, with a health "Doctor" and a Claude chat archiver. Decided against it: it does not find stale Claude sessions or MCP servers (MCP servers do not listen on ports), it has no prebuilt download (needs a Rust toolchain), and it is a young project.
- **Build our own**, small and specific to this problem. That became MacBar.

## 3. What MacBar does

One menu-bar icon (title like `🧹 84% · 4 ☕`: RAM used, stale count, keep-awake flag). Menu sections:

1. **MEMORY**: RAM, swap, free disk (with warnings), top 6 memory apps grouped by app, each with Quit or Force quit. "Purge inactive memory" (needs root).
2. **KEEP AWAKE** (Caffeine plus Amphetamine in one):
   - Lid open: an IOKit power assertion, no password. Durations: 15 min, 30 min, 1 h, 2 h, 4 h, 8 h, indefinite. Optional "keep screen on".
   - Lid closed: `pmset -a disablesleep 1` (needs root). When a duration is chosen, a root background timer reverts it by itself, tied to a token file so a later session is not cut short. Quit asks whether to turn it off first.
3. **CLAUDE SESSIONS & MCP**: lists and stops stale Claude sessions and orphaned MCP servers. Age filter: all running, 1 h, 3 h, 6 h, 12 h, 24 h (saved). "Clean now" and "Clean now + dev servers" (expo, vitest, vite). "All running sessions" asks for confirmation because it can stop the session you are using.
4. **DISK**: clears Xcode DerivedData, the npm cache and old Homebrew downloads (shows size, asks first).
5. **Launch at login** toggle (on by default after the first run), Refresh, Quit.

Active choices show an explicit `✓` in the title, because the native menu checkmark did not render on this machine (macOS 27.2).

## 4. Layout

```
bin/mcpclean       bash CLI: finds and stops stale sessions and MCP orphans
src/MenuBar.swift  the whole menu-bar app
Info.plist         LSUIElement app (no Dock icon)
build.sh           compiles to ~/Applications/MacBar.app, installs ~/.local/bin/mcpclean
release.sh         build.sh plus dist/MacBar.zip
```

Build: `./build.sh` (needs Xcode Command Line Tools). The app is ad-hoc signed, so on another Mac the first launch needs right-click, then Open.

## 5. How `mcpclean` decides what to stop

Dry run by default. `--kill` to act, `--dev` to include dev servers, `MAX_AGE_H` sets the stale age.

- A **stale session** is a process named `claude` older than `MAX_AGE_H` that is not part of the session running the command.
- An **MCP orphan** matches a known MCP command pattern (`mcp_re` in the script) and either its owning Claude session is stale, or it has no Claude owner and the top of its process chain is itself an MCP or npm wrapper.
- The session running `mcpclean`, its ancestors and its children are never touched.
- After stopping sessions it runs a second pass for children that were just orphaned.

To cover a new MCP server, add it to `mcp_re`.

## 6. Bug found during testing (fixed in v0.2.1)

The first version treated any MCP server whose owner was not Claude as an orphan. That would have killed MCP servers belonging to live apps such as Antigravity, Claude Desktop or Cursor. Reproduced with a fake host process, then fixed by requiring that the top of the chain is an MCP or npm wrapper rather than an app. Retested: live-host children survive, real orphans are stopped, the running session is untouched.

## 7. Touch ID instead of a password

The lid-closed mode needs root. Originally it used the AppleScript admin dialog, which only asked for a password. Now the app tries `sudo` first and falls back to the dialog.

One-time setup for Touch ID in `sudo` (macOS 14+, survives updates):

```sh
sudo sh -c 'sed "s/^#auth/auth/" /etc/pam.d/sudo_local.template > /etc/pam.d/sudo_local'
```

Verified: after enabling, `sudo -v` works without a terminal or password. Lid-closed mode with Touch ID inside the app: assumed working after the owner's test, not independently observed.

## 8. Test status

| Area | Status |
|---|---|
| `mcpclean` kill, orphan detection, session protection, `--dev` | Tested (fake processes) |
| Keep-awake power assertions | Tested (standalone program, visible in `pmset -g assertions`) |
| Lid-closed mode | Tested by the owner, works |
| Menu rendering, all buttons | Not verified by automated tests (accessibility could not read the menu) |
| Launch at login | Registered, not tested across a restart |
| Memory number | Computed from `vm_stat` (active, wired, compressed). About 19 GB when `top` showed 22 GB, so it reads a bit lower than Activity Monitor |

## 9. Known limits and open items

- Apple Silicon only in the release zip.
- The icon can be hidden by a menu bar manager (a `«` chevron was seen) or by a full menu bar. Expand the manager to find it.
- Lid-closed mode: do not carry the Mac in a bag while it is on. Manual off: `sudo pmset -a disablesleep 0`.
- Swap is not cleared by any of this. Only a restart fully frees it.
- Possible next steps: a shorter menu-bar title, Intel build, a Developer ID signature to remove the Gatekeeper warning, making the repo public.

## 10. Release history

| Version | Change |
|---|---|
| v0.1.0 | Memory view, session and MCP cleanup with age filter, disk cache cleaning |
| v0.2.0 | Keep awake (timed, indefinite, lid-closed) |
| v0.2.1 | Fix: live app-hosted MCP servers were wrongly treated as orphans |
| v0.2.2 | Explicit tick on active menu choices |
| v0.2.3 | Touch ID via sudo for lid-closed mode, password dialog as fallback |
