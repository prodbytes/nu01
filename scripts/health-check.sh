#!/usr/bin/env bash
# Health monitor for the dev server. On start it prints the local URLs once;
# then every HEALTH_CHECK_INTERVAL seconds (15 by default) one line: the time
# and, per check, an icon, a short label and ✅/❌. Runs via
# `devbox services up` (see process-compose.yaml) or standalone.
set -uo pipefail

INTERVAL="${HEALTH_CHECK_INTERVAL:-15}"
BASE="http://localhost:${NU01_PORT:-1415}"
HTTPS="https://${NU01_PUBLIC_HOST:-local.nu01.com}:${NU01_HTTPS_PORT:-1443}"
cd "$(dirname "$0")/.."
langs="$(find site/i18n -name '*.json' ! -name en.json -exec basename {} .json \; | sort | tr '\n' ' ')"

# mark <command...>: ✅ when the command succeeds, ❌ otherwise.
mark() { if "$@"; then printf ✅; else printf ❌; fi; }
page() { curl -fs --max-time 5 "$BASE$1" | grep -q "<html lang=\"$2\">"; }
# The certificate must verify: mkcert's CA, or the system store after `mkcert -install`.
https() {
  local ca=() root
  root="$(mkcert -CAROOT 2>/dev/null)/rootCA.pem" && [[ -s "$root" ]] && ca=(--cacert "$root")
  curl -fs --max-time 5 "${ca[@]}" "$HTTPS/version.json" | grep -q '"stage": "local"'
}
version() { curl -fs --max-time 5 "$BASE/version.json" | grep -q '"stage": "local"'; }

echo "nu01 local: $BASE/ ($(for lang in $langs; do printf '/%s/ ' "$lang"; done | sed 's/ $//')) and $HTTPS/"

while true; do
  line="$(date '+%Y-%m-%d %H:%M:%S') 🌐 en $(mark page / en)"
  for lang in $langs; do line+=" 🌐 $lang $(mark page "/$lang/" "$lang")"; done
  line+=" 🏷️ version $(mark version) 🔒 https $(mark https)"
  echo "$line"
  sleep "$INTERVAL"
done
