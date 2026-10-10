#!/usr/bin/env bash
# One-time setup, run by hand on a machine with the gh CLI (signed in to an
# account that can create prodbytes repositories) and admin AWS credentials:
#   1. creates github.com/prodbytes/nu01 (public) from this clone and pushes main
#   2. deploys the GitHub deploy roles (infra/github-deploy.yaml, stack
#      nu01-github-deploy), with the repository id pinned in their trust
#   3. sets the repository variables the deploy workflows read
#   4. cuts the first release candidate (scripts/release-rc.sh), which
#      deploys https://rc.nu01.com
# It never deploys GA: check the RC first, then run scripts/retire-legacy.sh
# and scripts/release-ga.sh (see README.md). Safe to re-run; each step skips
# what is already done.
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
REPO="${REPO:-prodbytes/nu01}"
VISIBILITY="${VISIBILITY:-public}"

echo "==> 1. GitHub repository $REPO"
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  gh repo create "$REPO" "--$VISIBILITY" --description "nu01.com is LEARNWARE: the nu01.com website" \
    --homepage https://nu01.com --source . --remote origin --push
else
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "git@github.com:$REPO.git"
  git push --quiet origin main
fi
owner_id="$(gh api "repos/$REPO" --jq .owner.id)"
repo_id="$(gh api "repos/$REPO" --jq .id)"
echo "    $REPO is owner $owner_id, repository $repo_id"

echo "==> 2. Deploy roles (stack nu01-github-deploy)"
zone="$(aws route53 list-hosted-zones-by-name --dns-name nu01.com --max-items 1 \
  --query "HostedZones[?Name=='nu01.com.' && Config.PrivateZone==\`false\`].Id | [0]" --output text)"
zone="${zone#/hostedzone/}"
create_provider=false
aws iam get-open-id-connect-provider --open-id-connect-provider-arn \
  "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/token.actions.githubusercontent.com" \
  >/dev/null 2>&1 || create_provider=true
aws cloudformation deploy --stack-name nu01-github-deploy \
  --template-file infra/github-deploy.yaml --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "HostedZoneId=$zone" "GitHubRepository=$REPO" \
    "GitHubImmutableRepository=${REPO%%/*}@$owner_id/${REPO##*/}@$repo_id" \
    "CreateOidcProvider=$create_provider" \
  --no-fail-on-empty-changeset
output() {
  aws cloudformation describe-stacks --stack-name nu01-github-deploy \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

echo "==> 3. Repository variables"
gh variable set AWS_DEPLOY_ROLE_ARN --repo "$REPO" --body "$(output DeployRoleArn)"
gh variable set AWS_DEPLOY_RC_ROLE_ARN --repo "$REPO" --body "$(output RcDeployRoleArn)"
gh variable set HOSTED_ZONE_ID --repo "$REPO" --body "$zone"

echo "==> 4. First release candidate"
if [[ -n "$(git tag --points-at HEAD --list '*-RC*')" ]]; then
  echo "    HEAD already has an RC tag; skipping"
else
  bash scripts/release-rc.sh
fi
echo "==> Done. Watch Deploy RC, then check https://rc.nu01.com/ before any GA."
