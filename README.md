# better-photography-workflow

A dependency-free, macOS-only command-line workflow assistant for photographers. It watches a project directory, creates a four-step project checklist in Apple Reminders, optionally creates a standard folder structure, and can incrementally copy projects to a genuinely mounted external volume with `rsync`.

The project uses only tools shipped with macOS: zsh, AppleScript/Reminders, launchd, rsync, and standard command-line utilities. It works on Apple Silicon and Intel Macs. It never modifies the internal contents of an Apple Photos Library.

中文说明：[README.zh-CN.md](README.zh-CN.md)

## Quick start

```zsh
./install.sh
export PATH="$HOME/.local/bin:$PATH"
bpw doctor
bpw new "Cat Portrait"
```

The default workspace is `~/Pictures/Photography_Work`. A new project receives the local date and standard subdirectories, then four due-dated reminders are added to the configured Reminders list.

## Commands

```text
bpw install
bpw uninstall [--purge]
bpw init
bpw new "project name"
bpw scan
bpw sync
bpw status
bpw doctor
bpw logs
bpw version
bpw config export
bpw config apply <file>
bpw help
```

See [installation](docs/installation.md), [configuration](docs/configuration.md), [permissions](docs/permissions.md), [workflow](docs/workflow.md), and [troubleshooting](docs/troubleshooting.md).

For the native macOS menu-bar and settings app, see the [GUI guide](docs/gui.md).

## Safety model

- Scanning is limited to first-level, non-hidden directories under `WORK_DIR`.
- Idempotency has two layers: a local marker keyed by the SHA-256 of the absolute project path, plus an AppleScript lookup for a matching reminder title, project path, and source marker.
- Scan and sync locks record both PID and process identity. A stale lock left by a crash or reboot is reclaimed automatically.
- Backup verifies the volume through both `diskutil` and the system mount table. The existence of `/Volumes/<name>` alone is never considered a mounted disk.
- `rsync` does not receive `--delete` unless `BACKUP_ALLOW_DELETE=true`. The default can only add or update destination files.
- Every backup destination component is checked for symlinks, real-path containment, and membership in the mounted volume's filesystem.
- `.DS_Store`, AppleDouble files (`._*`), and common temporary download files are excluded.
- The 1 MiB main log rotates with three backups, while `bpw status` reports the latest scan, sync, and successful-sync timestamps.

## Important configuration trust notice

The first release uses a **trusted local zsh configuration file** at `~/.config/better-photography-workflow/config`. It is sourced by `bpw`, so shell syntax in that file can execute with your user privileges. Do not copy an unreviewed config from the internet and do not let another user write it. Before loading, `bpw` requires a regular, non-symlink file owned by the current user and rejects group/world-writable permissions. Keep it at mode `600`.

## License

[MIT](LICENSE)
