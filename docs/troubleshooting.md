# Troubleshooting

## Start with doctor and logs

```zsh
bpw doctor
bpw status
bpw logs
```

Launchd stderr is stored at:

```text
~/.local/state/better-photography-workflow/logs/launchd-error.log
```

## Reminders are not created

Run `bpw scan` interactively and accept the macOS prompt. Then check:

```text
系统设置 → 隐私与安全性 → 提醒事项
系统设置 → 隐私与安全性 → 自动化
```

If the local state marker exists but reminders were manually deleted, remove only the marker identified for that project, or rename/recreate the project, then scan. Do not remove the whole state directory unless you want every project to be checked again. Reminders-side duplicate checks make a full recheck safe but slower.

## Config is rejected

The config must be a regular file owned by you and not writable by group/others:

```zsh
chmod 600 ~/.config/better-photography-workflow/config
zsh -n ~/.config/better-photography-workflow/config
```

Avoid literal newlines in path and label values. `WORK_DIR` and `BACKUP_DESTINATION` must be absolute.

## External volume appears in Finder but sync says not mounted

Confirm that `BACKUP_VOLUME_NAME` exactly matches the Finder volume name and inspect:

```zsh
diskutil info "/Volumes/PhotographySSD"
mount
```

The tool intentionally refuses a stale ordinary directory under `/Volumes`.

## launchd did not pick up config changes

Run `bpw install` after changing `WORK_DIR`, `SCAN_INTERVAL`, or `SYNC_INTERVAL`. This regenerates, validates, and reloads the user agents.

## rsync returned a nonzero code

- `20`: interrupted by a signal; reconnect if needed and retry.
- `23`: some files were not transferred; inspect permissions and log lines.
- `24`: source files disappeared during the run; often transient, retry once capture/import activity settles.

The exact rsync code is preserved for scripts and diagnostics.
