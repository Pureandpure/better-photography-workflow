# macOS permissions

## Reminders

`bpw scan` and `bpw new` control Apple Reminders through AppleScript. On first use, macOS may display a consent dialog. Allow access.

If creation fails, review both locations:

```text
系统设置
→ 隐私与安全性
→ 提醒事项
```

and:

```text
系统设置
→ 隐私与安全性
→ 自动化
```

Enable the terminal application used for manual commands. Background launchd execution may also require approval associated with `osascript`/Reminders. Run `bpw doctor`, then `bpw scan` interactively once to surface prompts.

## Files and folders

If `WORK_DIR` is under a privacy-protected location or on a removable drive, macOS may request Files and Folders access for Terminal or the process running the command. Grant only the required location.

The tool does not request or require direct access to the internal contents of an Apple Photos Library.

## Resetting a denied decision

Use System Settings first. If the app does not appear, run `bpw scan` interactively again. macOS privacy decisions are controlled by the OS; this project does not bypass or alter them.
