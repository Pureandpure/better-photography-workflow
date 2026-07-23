# Workflow

## Project discovery

The watch LaunchAgent responds to changes in `WORK_DIR`. A `StartInterval` compensation scan also runs every `SCAN_INTERVAL` seconds because filesystem events can be coalesced or missed while logged out. Each scan uses `find` with a depth of exactly one and ignores hidden directories.

`bpw new "猫咪写真"` creates `YYYY-MM-DD_猫咪写真` using the local date. If the supplied name already begins with `YYYY-MM-DD_`, it is used unchanged. Existing paths are errors and are never overwritten.

## Reminders

Due dates are based on the directory creation time (falling back to modification time if birth time is unavailable) in the local macOS calendar. Every reminder note contains:

```text
摄影项目路径：<absolute path>
任务说明：<configured description>
来源：better-photography-workflow
```

The local state marker is written only after AppleScript successfully creates or finds all four reminders.

## Duplicate prevention

Two independent layers make retries safe:

1. The SHA-256 of the absolute project path maps to a marker in `~/.local/state/better-photography-workflow/projects`.
2. Before each create, AppleScript searches the target list for a reminder with the same title and a note containing the same absolute project path and source marker.

An atomic scan lock prevents two local scanner processes from racing. The lock stores the PID and process start identity, so a lock left by a crash, forced termination, or reboot is reclaimed automatically. If a process stops after creating reminders but before writing state, the next scan reaches layer two, skips the existing reminders, and then repairs local state.

## Backup

With `ENABLE_BACKUP=true`, `bpw sync`:

1. validates configuration bounds the destination to `/Volumes/<configured name>`;
2. asks `diskutil` about that exact volume;
3. confirms the exact mount point in `/sbin/mount` output;
4. creates the destination only after mount verification;
5. rejects symlinks in every destination component and confirms the resolved path and filesystem still belong to the mounted volume;
6. runs one-way archive-mode rsync from `WORK_DIR/` to `BACKUP_DESTINATION/`.

The default excludes `.DS_Store`, `._*`, `*.download`, `*.crdownload`, `*.part`, and `*.tmp`. Interrupted transfers keep partial data for retry. Exit codes 20, 23, and 24 receive specific log messages; all nonzero rsync codes are propagated.

`BACKUP_ALLOW_DELETE=false` is the safety default. Set it to `true` only if the destination must become a strict mirror and you accept deletion of destination-only files.

## Runtime status and logs

Each scan and sync writes an atomic status record containing its timestamp, outcome, exit code, duration, and a short detail. Successful operations also keep a separate last-success record. `bpw status` summarizes these records.

The main log rotates at 1 MiB and keeps three previous files (`bpw.log.1` through `bpw.log.3`).
