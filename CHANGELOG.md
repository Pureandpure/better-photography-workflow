# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-07-19

### Added

- macOS-native `bpw` command with init, new, scan, sync, status, doctor, logs, install, and uninstall workflows.
- Apple Reminders task creation with configurable names, descriptions, due-day offsets, and time.
- Local SHA-256 state markers plus Reminders-side duplicate detection.
- Optional project folder scaffolding.
- Safe external-volume verification and non-deleting incremental rsync backup.
- User launchd agents for event-driven/compensation scans and scheduled backup attempts.
- English and Simplified Chinese documentation and a dependency-free test runner.
