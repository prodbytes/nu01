# infra

| Template | Stack | Holds |
|---|---|---|
| [site.yaml](site.yaml) | `nu01-web`, `nu01-rc-web` | https://nu01.com and https://rc.nu01.com: an ACM certificate (DNS-validated in the `nu01.com` zone), a private S3 bucket readable only by CloudFront (OAC), the distribution, a CloudFront Function for directory URIs, and Route 53 A/AAAA aliases |
| [github-deploy.yaml](github-deploy.yaml) | `nu01-github-deploy` | The `nu01-github-deploy` role (Deploy workflow, `*GA` tags) and `nu01-github-deploy-rc` (Deploy RC: `*RC*` tags and manual runs from `main`). Each may manage only its own stack and bucket, and change only its own records (`nu01.com` or `rc.nu01.com`, plus their ACM validation names). Neither can touch IAM. It reuses the account's GitHub OIDC provider (made by `presence-github-deploy`) |
| [zone.yaml](zone.yaml) | `nu01-route53-zone` | The `nu01.com` public hosted zone (from prodbytes/dsp, unchanged) |
| [gmail.yaml](gmail.yaml) | `nu01-route53-gmail` | Google Workspace MX and SPF for `nu01.com` (from prodbytes/dsp, unchanged) |
| [dns.yaml](dns.yaml) | `nu01-dns` | The apps' records merged into `nu01.com` from their old subzones (grigri, tabscan, rbacr, uplink), one `Migrate<Project>` switch each. See [specs/dns.md](../specs/dns.md) |
| [monitor.yaml](monitor.yaml) | `nu01-monitor` | Uptime checks for every nu01 app, GA and RC (replacing the per-project Route 53 health checks): a Lambda function run every 5 minutes by an EventBridge rule, its log group (14 days), the `nu01-health` SNS topic (email) and the `nu01-monitor-errors` alarm. See [specs/monitor.md](../specs/monitor.md) |

[scripts/deploy.sh](../scripts/deploy.sh) deploys `site.yaml`;
[scripts/bootstrap.sh](../scripts/bootstrap.sh) deploys `github-deploy.yaml`
once (run it again when the template changes):

```sh
aws cloudformation deploy --region us-east-1 --stack-name nu01-github-deploy \
  --template-file infra/github-deploy.yaml --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides HostedZoneId=<nu01.com zone> \
    GitHubImmutableRepository=prodbytes@288014477/nu01@<repository id> \
  --tags project=nu01 tenancy=shared
```

Every stack is tagged for cost allocation, and CloudFormation copies the
tags to its resources: `project=nu01`, and `tenancy=GA` (`nu01-web`), `RC`
(`nu01-rc-web`) or `shared` (`nu01-github-deploy`, `nu01-route53-zone`, `nu01-route53-gmail`,
`nu01-dns`, `nu01-monitor`).

This repository owns the shared nu01 infrastructure: the `nu01.com` zone and
mail records, the apps' records in it, and the monitor.
[scripts/deploy-dns.sh](../scripts/deploy-dns.sh) deploys `zone.yaml`,
`gmail.yaml` and `dns.yaml` (same parameters as before, so only the tags
change); [scripts/migrate-subzone.sh](../scripts/migrate-subzone.sh)
`<project>` merges one subzone into `nu01.com` (dry run unless
`CONFIRM=yes`; runbook and timing in [specs/dns.md](../specs/dns.md)).

[scripts/deploy-monitor.sh](../scripts/deploy-monitor.sh) deploys
`monitor.yaml`, by hand (CI's roles can't), then runs the checks once. To
add an endpoint, add a line to the template's `Endpoints` parameter and run
it again. It costs about $0 (Lambda, the schedule and one alarm fit in the
free tiers), against about $24/month for the 14 Route 53 health checks it
replaced.

The site buckets are kept (`DeletionPolicy: Retain`) if a stack is deleted.
