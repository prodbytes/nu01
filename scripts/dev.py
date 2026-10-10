#!/usr/bin/env python3
"""The local dev server: builds the site, serves it, and rebuilds on change.

    python3 scripts/dev.py            # http://localhost:1415/
                                      # https://local.nu01.com:1443/

- Builds with scripts/build.py --stage local (pages marked LOCAL) into
  dist/dev/, then serves that folder like CloudFront does: directory URIs
  serve their index.html, and a directory without its slash (/es) is
  redirected to it (301).
- Every second it checks site/, site_local/ and scripts/build.py; on a
  change it rebuilds into dist/dev.new/ and swaps it in, so a page is never
  half built. A failed build (e.g. a bundle missing a key) is printed and
  the last good build keeps being served.
- It also serves HTTPS on NU01_HTTPS_PORT (1443) when the certificate from
  scripts/local-certs.sh is in certs/; local.nu01.com resolves to 127.0.0.1.
- Settings, from the environment: NU01_PORT (1415), NU01_HTTPS_PORT (1443),
  NU01_PUBLIC_HOST (local.nu01.com), NU01_BIND_HOST (127.0.0.1; 0.0.0.0 in
  a container).
"""
import functools
import http.server
import os
import shutil
import ssl
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "dist" / "dev"
WATCHED = [ROOT / "site", ROOT / "site_local", ROOT / "scripts" / "build.py"]
PORT = int(os.environ.get("NU01_PORT", "1415"))
HTTPS_PORT = int(os.environ.get("NU01_HTTPS_PORT", "1443"))
PUBLIC_HOST = os.environ.get("NU01_PUBLIC_HOST", "local.nu01.com")
HOST = os.environ.get("NU01_BIND_HOST", "127.0.0.1")
CERT = ROOT / "certs" / "local.pem"
KEY = ROOT / "certs" / "local-key.pem"


def snapshot():
    """The newest modification time and the file count under WATCHED."""
    newest, count = 0.0, 0
    for path in WATCHED:
        files = [path] if path.is_file() else [p for p in path.rglob("*") if p.is_file()]
        for f in files:
            try:
                newest = max(newest, f.stat().st_mtime)
                count += 1
            except FileNotFoundError:
                pass
    return newest, count


def build():
    """Builds into dist/dev.new/ and swaps it in; returns True on success."""
    staging = OUT.with_name("dev.new")
    try:
        commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                                capture_output=True, text=True).stdout.strip() or "unknown"
    except OSError:
        commit = "unknown"
    started = time.time()
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "build.py"), "--stage", "local",
         "--origin", f"http://localhost:{PORT}", "--version", "0.0.0-local",
         "--commit", commit, "--out", str(staging)],
        capture_output=True, text=True)
    if result.returncode != 0:
        print(f"✗ build failed; still serving the last good build\n{result.stderr.strip()}", flush=True)
        shutil.rmtree(staging, ignore_errors=True)
        return False
    old = OUT.with_name("dev.old")
    shutil.rmtree(old, ignore_errors=True)
    if OUT.exists():
        OUT.rename(old)
    staging.rename(OUT)
    shutil.rmtree(old, ignore_errors=True)
    print(f"✓ built in {time.time() - started:.1f}s", flush=True)
    return True


class Handler(http.server.SimpleHTTPRequestHandler):
    # No caching, so a reload always shows the latest build.
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        if not str(args[1] if len(args) > 1 else "").startswith("2"):
            super().log_message(fmt, *args)


def serve():
    handler = functools.partial(Handler, directory=str(OUT))
    server = http.server.ThreadingHTTPServer((HOST, PORT), handler)
    print(f"serving http://localhost:{PORT}/ (en), /es/, /pt/, /ca/", flush=True)
    server.serve_forever()


def serve_https():
    """HTTPS with the mkcert certificate, when scripts/local-certs.sh made one."""
    if not (CERT.is_file() and KEY.is_file()):
        print("no certs/local.pem; run scripts/local-certs.sh for HTTPS", flush=True)
        return
    handler = functools.partial(Handler, directory=str(OUT))
    server = http.server.ThreadingHTTPServer((HOST, HTTPS_PORT), handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(CERT, KEY)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f"serving https://{PUBLIC_HOST}:{HTTPS_PORT}/", flush=True)
    server.serve_forever()


def main():
    if not build():
        sys.exit(1)
    threading.Thread(target=serve, daemon=True).start()
    threading.Thread(target=serve_https, daemon=True).start()
    last = snapshot()
    try:
        while True:
            time.sleep(1)
            now = snapshot()
            if now != last:
                last = now
                time.sleep(0.2)  # let an editor finish writing
                build()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
