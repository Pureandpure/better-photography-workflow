# Contributing

Keep the project macOS-native and dependency-free. Changes must continue to support spaces, non-ASCII text, shell metacharacters, and arbitrary user home paths.

Before opening a pull request:

```zsh
for script in bin/bpw lib/common.sh scripts/*.sh install.sh uninstall.sh tests/run-tests.sh app/build-app.sh; do
  zsh -n "$script"
done
./tests/run-tests.sh
swift test --package-path app
git diff --check
```

Do not weaken the trusted-config ownership checks, mounted-volume verification, destination containment checks, or the default non-deleting backup behavior. Include focused tests for changes to scanning, Reminders, installation, launchd, or rsync handling.
