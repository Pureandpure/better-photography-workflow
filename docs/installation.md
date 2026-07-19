# Installation

## Requirements

- macOS on Apple Silicon or Intel
- Apple Reminders
- The macOS-provided zsh, osascript, launchd, rsync, plutil, find, and shasum

No Homebrew, Node.js, Python, or other package manager is required.

## Install

From a local checkout:

```zsh
./install.sh
```

The installer:

1. copies application files to `~/.local/share/better-photography-workflow`;
2. installs `bpw` at `~/.local/bin/bpw`;
3. creates the config only if it does not already exist;
4. creates the workspace and state/log directories;
5. renders and validates two user LaunchAgent plists;
6. loads the scan and backup agents in the current GUI login session.

If `~/.local/bin` is not in `PATH`, add this to `~/.zshrc`:

```zsh
export PATH="$HOME/.local/bin:$PATH"
```

Then run:

```zsh
bpw doctor
```

The first command that talks to Reminders may cause macOS to ask for permission.

## Update

Run `./install.sh` again from the newer checkout. Existing user configuration and state markers are preserved, and LaunchAgents are regenerated from the current configuration.

After changing `WORK_DIR`, `SCAN_INTERVAL`, or `SYNC_INTERVAL`, rerun `bpw install` so the generated plists contain the new values.

## Uninstall

```zsh
bpw uninstall
```

This removes the installed program and LaunchAgents but preserves config, state, logs, photography projects, and backups. To also remove user config/state/logs:

```zsh
bpw uninstall --purge
```

Neither mode deletes photography projects or external-drive backups.
