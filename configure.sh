#!/usr/bin/env bash
# configure.sh — Wrapper: runs only the TUI wizard
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/install.sh" --configure "$@"
