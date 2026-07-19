# Configuration

The installed config is:

```text
~/.config/better-photography-workflow/config
```

`bpw init` copies the complete example and never overwrites an existing file. The main settings are:

- `WORK_DIR`: absolute project workspace path.
- `REMINDER_LIST_NAME`: Apple Reminders list. It is created if missing.
- `AUTO_CREATE_PROJECT_STRUCTURE`: `true` or `false`.
- `PROJECT_SUBDIRECTORIES`: zsh array of relative directories.
- `REMINDER_HOUR`, `REMINDER_MINUTE`: local 24-hour due time.
- `TASK_1_*` through `TASK_4_*`: title suffix, days after project creation, and note description.
- `ENABLE_BACKUP`: turns external backup attempts on or off.
- `BACKUP_VOLUME_NAME`: exact Finder volume name.
- `BACKUP_DESTINATION`: absolute path inside that volume.
- `BACKUP_ALLOW_DELETE`: default `false`. When `true`, rsync deletion is explicitly enabled.
- `SCAN_INTERVAL`: launchd compensation-scan interval in seconds.
- `SYNC_INTERVAL`: launchd backup-attempt interval in seconds.

Example:

```zsh
WORK_DIR="$HOME/Pictures/Photography_Work"
REMINDER_LIST_NAME="摄影工作流"
REMINDER_HOUR=20
REMINDER_MINUTE=0
ENABLE_BACKUP=false
BACKUP_VOLUME_NAME="PhotographySSD"
BACKUP_DESTINATION="/Volumes/$BACKUP_VOLUME_NAME/Photography/01_Projects"
BACKUP_ALLOW_DELETE=false
```

Paths are quoted throughout the implementation and support spaces, Chinese text, shell metacharacters, and arbitrary usernames. Config values containing literal newlines are rejected because they make logs and launchd configuration ambiguous.

## Trust boundary

This version intentionally uses a trusted local zsh config. Sourcing a config can execute commands with your account privileges. Review the file, never install an untrusted copy, and keep it private:

```zsh
chmod 600 ~/.config/better-photography-workflow/config
```

Before sourcing, bpw verifies that it is a normal non-symlink file, is owned by the current user, is not group/world writable, and passes `zsh -n`. These checks reduce accidental exposure but do not sandbox the content.

## Applying changes

Most values are read at every invocation. Rerun `bpw install` after changing paths or intervals so LaunchAgent files are regenerated and reloaded.
