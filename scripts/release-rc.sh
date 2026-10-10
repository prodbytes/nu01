#!/usr/bin/env bash
# Tags the current commit as a release candidate, X.Y.Z-RC (Z is the current
# time), and pushes it; Deploy RC publishes it to https://rc.nu01.com.
# DRY_RUN=1 only prints the tag. See scripts/tag-release.sh.
set -euo pipefail
exec bash "$(dirname "$0")/tag-release.sh" RC
