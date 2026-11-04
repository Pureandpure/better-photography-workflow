#!/bin/zsh
# Compatibility entry point for older installed clients. Project state is now keyed by UUID.
set -u
SCRIPT_DIR="${0:A:h}"
BPW_ROOT="${BPW_ROOT:-${SCRIPT_DIR:h}}"
exec "$BPW_ROOT/scripts/workflow-engine.sh" projects "$@"
