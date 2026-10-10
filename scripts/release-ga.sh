#!/usr/bin/env bash
# Tags the current commit, which must be on main and already live on
# https://rc.nu01.com, as X.Y.Z-GA (Z is the current time), and pushes it;
# Deploy publishes it to https://nu01.com. DRY_RUN=1 only prints the tag.
# See scripts/tag-release.sh.
set -euo pipefail
exec bash "$(dirname "$0")/tag-release.sh" GA
