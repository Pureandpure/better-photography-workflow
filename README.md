# Creator Workflow for macOS

A native macOS workflow for video creators. The SwiftUI app reads real project directories from a configurable primary media library, tracks production stages and Done state, infers source devices from the folder hierarchy, and keeps optional second-copy backup automation in the existing `bpw` backend.

The project uses only tools shipped with macOS: SwiftUI, zsh, AppleScript/Reminders, launchd, rsync, and standard command-line utilities. It works on Apple Silicon and Intel Macs. It never modifies the internal contents of an Apple Photos Library.

中文说明：[README.zh-CN.md](README.zh-CN.md)

## Quick start

```zsh
./install.sh
export PATH="$HOME/.local/bin:$PATH"
bpw doctor
bpw new "Cat Portrait"
```

The default workspace is `~/Pictures/Photography_Work`. A new project receives the local date and standard subdirectories, then four due-dated reminders are added to the configured Reminders list.

## Media folders and Final Cut Pro

New imports use `01_MEDIA/VIDEO/<date>/<device>`, `01_MEDIA/PHOTO/<date>/<device>/RAW|JPEG`, and `01_MEDIA/AUDIO/<date>/<recorder>`. In Final Cut Pro choose `01_MEDIA/VIDEO`, optionally `01_MEDIA/AUDIO`, select “Leave files in place”, and optionally “From folders” for keywords. This workflow has not been validated in a real FCP session. Run `bpw migrate-media-layout --project <UUID>` to preview a single legacy project and add `--execute` only when ready. See [ingest](docs/ingest.md).

## Photography ingest MVP

See [setup, travel steps, safety and validation limits](docs/ingest.md). Stable Project IDs, UUID-based external workspaces, camera ingest, resumable copy, manifests, conservative Session matching and Primary-project backups are available through the CLI, with basic GUI import controls. Source media is retained.

## Commands

```text
bpw install
bpw uninstall [--purge]
bpw init
bpw new "project name"
bpw scan
bpw sync
bpw status
bpw projects list
bpw projects set-stage <project-path> <stage>
bpw projects set-favorite <project-path> <true|false>
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

- Scanning covers online Primary workspaces; see [ingest and migration](docs/ingest.md).
- Stable project UUIDs migrate existing path-hash reminder and workflow state without deleting old markers; reminders retain legacy-path compatibility.
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
