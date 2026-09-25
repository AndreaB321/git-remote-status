#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$GIT_CALL_LOG"
exec /usr/bin/git "$@"
