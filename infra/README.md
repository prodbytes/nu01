# infra

| Template | Stack | Holds |
|---|---|---|
| [site.yaml](site.yaml) | `nu01-web`, `nu01-rc-web` | https://nu01.com and https://rc.nu01.com: an ACM certificate (DNS-validated in the `nu01.com` zone), a private S3 bucket readable only by CloudFront (OAC), the distribution, a CloudFront Function for directory URIs, and Route 53 A/AAAA aliases |
| [github-deploy.yaml](github-deploy.yaml) | `nu01-github-deploy` | The `nu01-github-deploy` role (Deploy workflow, `*GA` tags) and `nu01-github-deploy-rc` (Deploy RC: `*RC*` tags and manual runs from `main`). Each may manage only its own stack and bucket, and change only its own records (`nu01.com` or `rc.nu01.com`, plus their ACM validation names). Neither can touch IAM. It reuses the account's GitHub OIDC provider (made by `presence-github-deploy`) |

[scripts/deploy.sh](../scripts/deploy.sh) deploys `site.yaml`;
[scripts/bootstrap.sh](../scripts/bootstrap.sh) deploys `github-deploy.yaml`
once (run it again when the template changes):

```sh
aws cloudformation deploy --region us-east-1 --stack-name nu01-github-deploy \
  --template-file infra/github-deploy.yaml --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides HostedZoneId=<nu01.com zone> \
    GitHubImmutableRepository=prodbytes@288014477/nu01@<repository id>
```

The site buckets are kept (`DeletionPolicy: Retain`) if a stack is deleted.
