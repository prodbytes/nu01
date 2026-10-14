# Deploy

[scripts/deploy.sh](../scripts/deploy.sh) (`STAGE=prod` or `rc`) builds the
site, deploys [infra/site.yaml](../infra/site.yaml), uploads `dist/site/`
and invalidates CloudFront, then smoke-tests the live site.

| | Production | Release candidate |
|---|---|---|
| URL | https://nu01.com | https://rc.nu01.com |
| Stack | `nu01-web` | `nu01-rc-web` |
| Workflow | [deploy.yml](../.github/workflows/deploy.yml), `*GA` tags | [deploy-rc.yml](../.github/workflows/deploy-rc.yml), `*RC*` tags and manual runs |
| Role | `nu01-github-deploy` (`AWS_DEPLOY_ROLE_ARN`) | `nu01-github-deploy-rc` (`AWS_DEPLOY_RC_ROLE_ARN`) |

- **Distribution:** HTTP/2 and 3, IPv6, TLS 1.2+, HTTPS only, the managed
  security headers. A CloudFront Function serves `index.html` for directory
  URIs and redirects `/es` to `/es/`. The bucket is private (OAC).
- **Caching:** pages and `version.json` are uploaded `no-cache`; the rest
  `max-age=3600`. Every deploy invalidates `/*`.
- **Smoke test** (retried up to 10 minutes): `/version.json` reports this
  version and commit, `/` is the site, every `/<lang>/` page answers in its
  language, and `/es` redirects with 301.
- **Roles** are keyless (GitHub OIDC). Each can manage only its own stack
  and bucket, and change only its own records and their ACM validation
  names. The repository variable `HOSTED_ZONE_ID` names the `nu01.com`
  zone (deploy.sh looks it up by name otherwise).
- **Tags:** each stack, and so each of its resources, carries the
  cost-allocation tags `project=nu01` and `tenancy=GA` or `RC`.
- **One-time setup:** [scripts/bootstrap.sh](../scripts/bootstrap.sh).
- **Uptime:** the nu01 apps are watched by the separate
  `nu01-monitor` stack ([monitor.md](monitor.md)), not by Route 53 health
  checks.

## Retiring the old site

Before this repository, https://nu01.com was a CloudFront distribution in
front of S3 that redirected to https://prodbytes.substack.com/. CloudFront
lets only one distribution hold the `nu01.com` alias, so it must go before
the first GA. [scripts/retire-legacy.sh](../scripts/retire-legacy.sh)
prints what it found; with `CONFIRM=yes` it backs up the origin buckets to
`legacy-backup/`, deletes the apex A/AAAA records, disables and deletes the
distribution, deletes the buckets and the certificate (or deletes the stack
that owns them). The apex is down until the GA deploy finishes, so run
`scripts/release-ga.sh` right after. RC deploys don't need this.
