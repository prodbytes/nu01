#!/usr/bin/env bash
# Health monitor for the dev server: every HEALTH_CHECK_INTERVAL seconds (15
# by default), one line with the time and ✅/❌ per check. Runs via
# `devbox services up` (see process-compose.yaml) or standalone.
set -uo pipefail

INTERVAL="${HEALTH_CHECK_INTERVAL:-15}"
BASE="http://localhost:${NU01_PORT:-8090}"
cd "$(dirname "$0")/.."
langs="$(find site/i18n -name '*.json' ! -name en.json -exec basename {} .json \; | sort | tr '\n' ' ')"

# mark <command...>: ✅ when the command succeeds, ❌ otherwise.
mark() { if "$@"; then printf ✅; else printf ❌; fi; }
page() { curl -fs --max-time 5 "$BASE$1" | grep -q "<html lang=\"$2\">"; }
version() { curl -fs --max-time 5 "$BASE/version.json" | grep -q '"stage": "local"'; }

while true; do
  line="$(date '+%Y-%m-%d %H:%M:%S') 🌐 en $(mark page / en)"
  for lang in $langs; do line+=" $lang $(mark page "/$lang/" "$lang")"; done
  line+=" 🏷️ version $(mark version)"
  echo "$line"
  sleep "$INTERVAL"
done
