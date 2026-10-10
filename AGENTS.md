# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path, not just a syntax check. For this repo that means
  `bash scripts/build.sh` (both `STAGE=prod` and `STAGE=rc`) succeeds, the
  built pages in `dist/site/` have no unresolved placeholders, and
  `devbox services up` starts the dev server with every health check ✅,
  and the site looks right on it in every language.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, and unnecessarily broad permissions (IAM roles in
  [infra/github-deploy.yaml](infra/github-deploy.yaml) stay scoped to this
  site's stacks, buckets and records). Never commit credentials, even
  placeholders that look real.

Do not commit or push code that has not passed both checks.

## Project notes

- A static site: no framework and no build tools beyond Python 3. The
  template is [site/index.html](site/index.html) (HTML5 UP's Dimension);
  [scripts/build.py](scripts/build.py) renders it once per language bundle.
- Toolchain (Python, AWS CLI, gh, process-compose) is in
  [devbox.json](devbox.json); enter it with `devbox shell`.
- `devbox services up` starts the processes in
  [process-compose.yaml](process-compose.yaml): the dev server
  (http://localhost:1415/) and the health monitor
  ([scripts/health-check.sh](scripts/health-check.sh)); stop with
  `devbox services stop`. In non-interactive contexts pass
  `--pcflags "--tui=false"`.
- Infrastructure is CloudFormation in [infra/](infra/), deployed by
  [scripts/deploy.sh](scripts/deploy.sh) from GitHub Actions.
