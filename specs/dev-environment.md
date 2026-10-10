# Dev environment

- **Toolchain:** [devbox.json](../devbox.json): Python, the AWS CLI, gh,
  curl, make and process-compose. `devbox shell` enters it.
- **`devbox services up`** starts [process-compose.yaml](../process-compose.yaml):

  | Process | What it does |
  |---|---|
  | `1-site` | [scripts/dev.py](../scripts/dev.py): the dev server on http://localhost:8090/ (`NU01_PORT`), bound to `127.0.0.1` (`NU01_BIND_HOST`; `0.0.0.0` in a container). Ready when `/version.json` answers |
  | `0-health-check` | [scripts/health-check.sh](../scripts/health-check.sh): every 15 s (`HEALTH_CHECK_INTERVAL`), one line with ✅/❌ for each language page (`<html lang>` must match) and for `/version.json` reporting the `local` stage. Starts once `1-site` is ready |

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
