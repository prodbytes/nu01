#!/usr/bin/env bash
# Generates the dev server's HTTPS certificate with mkcert, only when it's
# missing, expires within 30 days, doesn't cover every name below, or wasn't
# signed by this machine's mkcert CA. Runs before the dev server starts
# (process-compose.yaml) or standalone.
#
# The certificate is signed by mkcert's local CA (`mkcert -CAROOT`). mkcert
# creates the CA on first use; browsers trust it only after a one-time
# `mkcert -install`. The files live in certs/, which git ignores: never
# commit the key.
set -euo pipefail

CERT_DIR="$(cd "$(dirname "$0")/.." && pwd)/certs"
CERT="$CERT_DIR/local.pem"
KEY="$CERT_DIR/local-key.pem"
# local.nu01.com is a public name that resolves to 127.0.0.1 (an A record in
# Route 53, zone nu01.com), so https://local.nu01.com:<port> works locally.
NAMES=("${NU01_PUBLIC_HOST:-local.nu01.com}" localhost 127.0.0.1 ::1)

if ! command -v mkcert >/dev/null 2>&1; then
    echo "local-certs: 'mkcert' is not on PATH; run inside devbox (devbox shell / devbox services up)" >&2
    exit 1
fi

covers_all_names() {
    local sans
    sans="$(openssl x509 -in "$CERT" -noout -ext subjectAltName 2>/dev/null)" || return 1
    for name in "${NAMES[@]}"; do
        case "$name" in
            # openssl prints ::1 in full
            ::1) grep -q -F "IP Address:0:0:0:0:0:0:0:1" <<<"$sans" || return 1 ;;
            [0-9]*) grep -q -F "IP Address:$name" <<<"$sans" || return 1 ;;
            *) grep -q -F "DNS:$name" <<<"$sans" || return 1 ;;
        esac
    done
}

signed_by_this_ca() {
    local ca
    ca="$(mkcert -CAROOT)/rootCA.pem"
    [[ -s "$ca" ]] && openssl verify -CAfile "$ca" "$CERT" >/dev/null 2>&1
}

if [[ -s "$CERT" && -s "$KEY" ]] \
        && openssl x509 -in "$CERT" -noout -checkend $((30 * 24 * 3600)) >/dev/null 2>&1 \
        && covers_all_names && signed_by_this_ca; then
    echo "local-certs: $CERT is valid; nothing to do"
    exit 0
fi

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"
mkcert -cert-file "$CERT" -key-file "$KEY" "${NAMES[@]}"
chmod 600 "$KEY"
echo "local-certs: wrote $CERT (CA: $(mkcert -CAROOT)/rootCA.pem)"
