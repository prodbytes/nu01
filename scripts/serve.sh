#!/usr/bin/env bash
# Runs the dev server without devbox: http://localhost:${NU01_PORT:-1415}/,
# rebuilt on every change (scripts/dev.py). Ctrl-C stops it.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 scripts/dev.py
