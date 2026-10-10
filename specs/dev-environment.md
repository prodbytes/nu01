# Dev environment

- **Toolchain:** [devbox.json](../devbox.json): Python, the AWS CLI, gh,
  curl, make, process-compose, mkcert and openssl. `devbox shell` enters it.
- **`devbox services up`** starts [process-compose.yaml](../process-compose.yaml):

  | Process | What it does |
  |---|---|
  | `2-local-certs` | [scripts/local-certs.sh](../scripts/local-certs.sh): the mkcert certificate for `local.nu01.com`, `localhost`, `127.0.0.1` and `::1` in `certs/` (git-ignored, key mode 600), made only when missing, within 30 days of expiry, missing a name, or not signed by this machine's mkcert CA |
  | `1-site` | [scripts/dev.py](../scripts/dev.py): the dev server on http://localhost:1415/ (`NU01_PORT`) and https://local.nu01.com:1443/ (`NU01_HTTPS_PORT`, `NU01_PUBLIC_HOST`; only when the certificate exists), bound to `127.0.0.1` (`NU01_BIND_HOST`; `0.0.0.0` in a container). Starts after `2-local-certs`; ready when `/version.json` answers |
  | `0-health-check` | [scripts/health-check.sh](../scripts/health-check.sh): prints the local URLs (HTTP with each language's path, and HTTPS) once at start, then every 15 s (`HEALTH_CHECK_INTERVAL`) one line: the time and, per check, an icon, a short label and ✅/❌ — `🌐 <lang>` for each language page (`<html lang>` must match), `🏷️ version` for `/version.json` reporting the `local` stage, and `🔒 https` for the same over HTTPS with a verified certificate. Starts once `1-site` is ready |

  `devbox services stop` stops them; `devbox run dev` is the same as
  `devbox services up`. Without devbox, `bash scripts/serve.sh` (or `make
  serve`) runs the dev server alone.
- **The dev server** builds with `scripts/build.py --stage local` into
  `dist/dev/` (git-ignored): titles prefixed "🛠 LOCAL ·", a blue LOCAL
  badge and "DEV" favicon ([site_local/](../site_local)), crawlers kept out,
  canonical and `hreflang` URLs on `http://localhost:<port>`, version
  `0.0.0-local` with the current commit. It serves directory URIs as their
  `index.html`, redirects `/es` to `/es/` (as CloudFront does), and sends
  `Cache-Control: no-store`.
- **Rebuilds:** every second it checks `site/`, `site_local/` and
  `scripts/build.py`; a change rebuilds into `dist/dev.new/`, swapped in
  whole. A failed build (e.g. a bundle missing a key) is printed and the
  last good build stays up.
- **Local HTTPS:** `local.nu01.com` is an A record → `127.0.0.1` (TTL 300)
  in the Route 53 zone `nu01.com`, created by hand (like
  `local.presence.nu01.com`), not by CloudFormation. Browsers trust the
  certificate after a one-time `mkcert -install` on each machine.
