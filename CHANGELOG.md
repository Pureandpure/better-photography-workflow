# Changelog

All notable changes to this project will be documented in this file.

## [0.3.1] - 2026-07-23

### Added

- `bpw app` opens the installed native macOS application.

## [0.3.0] - 2026-07-23

### Added

- Recoverable PID-and-process-identity locks for scans and syncs.
- Real-path, symlink, and filesystem checks for backup destinations.
- Atomic operation status records, successful-sync history, log rotation, and `bpw version`.
- macOS GitHub Actions CI and expanded backup, locking, rotation, and installer rollback tests.
- Native SwiftUI menu-bar and settings application with project, Reminders, backup, diagnostics, and log controls.
- Validated plist configuration bridge with JSON export for GUI clients.

### Changed

- Installation now stages and validates a complete release before replacement and restores the previous installation if LaunchAgent loading fails.
- The default Reminders list is consistently named `🍎摄影工作流`.

## [0.1.0] - 2026-07-19

### Added

- macOS-native `bpw` command with init, new, scan, sync, status, doctor, logs, install, and uninstall workflows.
- Apple Reminders task creation with configurable names, descriptions, due-day offsets, and time.
- Local SHA-256 state markers plus Reminders-side duplicate detection.
- Optional project folder scaffolding.
- Safe external-volume verification and non-deleting incremental rsync backup.
- User launchd agents for event-driven/compensation scans and scheduled backup attempts.
- English and Simplified Chinese documentation and a dependency-free test runner.
