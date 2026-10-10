#!/usr/bin/env bash
# Deploys the site to production, https://nu01.com, or with STAGE=rc to the
# release candidate, https://rc.nu01.com:
#   1. builds the site (scripts/build.sh) for the stage
#   2. deploys the stack (infra/site.yaml: nu01-web or nu01-rc-web)
#   3. uploads dist/site/ to its bucket and invalidates CloudFront
#   4. smoke-tests the live site: /version.json must report this version
#      and commit, every language page must answer, and /es must redirect
#      to /es/
#
# Run by .github/workflows/deploy.yml (*GA tags) and deploy-rc.yml (*RC*
# tags, manual runs from main), or by hand with admin credentials.
# Settings, from the environment:
#   TAG             the release tag, X.Y.Z-KK (default: none, Z = now)
#   STAGE           prod (default) or rc
#   HOSTED_ZONE_ID  the nu01.com Route 53 zone (default: looked up by name)
#   AWS_REGION      default us-east-1 (CloudFront certificates live there)
# A first production deploy needs https://nu01.com's old distribution and
# records gone (scripts/retire-legacy.sh), or the stack can't take them.
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
STAGE="${STAGE:-prod}"
case "$STAGE" in
  prod) STACK=nu01-web; DOMAIN=nu01.com ;;
  rc) STACK=nu01-rc-web; DOMAIN=rc.nu01.com ;;
  *) echo "error: STAGE must be prod or rc (got '$STAGE')" >&2; exit 2 ;;
esac

# 1. Build (sets VERSION through scripts/version.sh, from TAG)
STAGE="$STAGE" TAG="${TAG:-}" bash scripts/build.sh
VERSION="$(python3 -c 'import json; print(json.load(open("dist/site/version.json"))["version"])')"
COMMIT="$(python3 -c 'import json; print(json.load(open("dist/site/version.json"))["commit"])')"
echo "==> deploying $VERSION ($COMMIT) to https://$DOMAIN/ ($STAGE, $AWS_REGION)"

stack_output() { # stack_output <output key>
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

if [[ -z "${HOSTED_ZONE_ID:-}" ]]; then
  HOSTED_ZONE_ID="$(aws route53 list-hosted-zones-by-name --dns-name nu01.com --max-items 1 \
    --query "HostedZones[?Name=='nu01.com.' && Config.PrivateZone==\`false\`].Id | [0]" --output text)"
  HOSTED_ZONE_ID="${HOSTED_ZONE_ID#/hostedzone/}"
fi
if [[ ! "$HOSTED_ZONE_ID" =~ ^Z[A-Z0-9]+$ ]]; then
  echo "error: no nu01.com hosted zone (got '$HOSTED_ZONE_ID'); set HOSTED_ZONE_ID" >&2
  exit 1
fi

# 2. The stack
echo "==> deploying $STACK"
aws cloudformation deploy --stack-name "$STACK" --template-file infra/site.yaml \
  --parameter-overrides "DomainName=$DOMAIN" "HostedZoneId=$HOSTED_ZONE_ID" \
  --no-fail-on-empty-changeset
bucket="$(stack_output SiteBucketName)"
distribution="$(stack_output DistributionId)"
echo "    bucket: $bucket, distribution: $distribution"

# 3. The content. Pages and version.json are revalidated on every visit;
# assets are cached for an hour (their names aren't content-hashed).
echo "==> uploading"
aws s3 sync dist/site/ "s3://$bucket/" --delete --only-show-errors \
  --exclude '*.html' --exclude 'version.json' --cache-control 'public, max-age=3600'
aws s3 sync dist/site/ "s3://$bucket/" --only-show-errors --exclude '*' \
  --include '*.html' --include 'version.json' --cache-control no-cache
invalidation="$(aws cloudfront create-invalidation --distribution-id "$distribution" \
  --paths '/*' --query Invalidation.Id --output text)"
echo "    waiting for invalidation $invalidation"
aws cloudfront wait invalidation-completed --distribution-id "$distribution" --id "$invalidation"

# 4. Smoke test (retried: on a first deploy DNS and the edge take a moment)
echo "==> checking https://$DOMAIN/"
langs="$(find site/i18n -name '*.json' ! -name en.json -exec basename {} .json \; | sort)"
check() {
  local live
  live="$(curl -fsS --max-time 20 "https://$DOMAIN/version.json?deploy=$VERSION_CHECK" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["version"], d["commit"])')" || return 1
  [[ "$live" == "$VERSION $COMMIT" ]] || { echo "    /version.json says $live, want $VERSION $COMMIT"; return 1; }
  curl -fsS --max-time 20 "https://$DOMAIN/" | grep -q 'LEARNWARE' || { echo "    / isn't the site"; return 1; }
  local lang code
  for lang in $langs; do
    curl -fsS --max-time 20 "https://$DOMAIN/$lang/" | grep -q "<html lang=\"$lang\">" \
      || { echo "    /$lang/ isn't the $lang page"; return 1; }
  done
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$DOMAIN/es")"
  [[ "$code" == 301 ]] || { echo "    /es answered $code, want 301"; return 1; }
}
VERSION_CHECK="$(date -u +%s)"
for attempt in $(seq 1 30); do
  if check; then
    echo "==> https://$DOMAIN/ serves $VERSION ($COMMIT)"
    exit 0
  fi
  echo "    not yet (attempt $attempt/30); retrying in 20 s"
  sleep 20
done
echo "error: https://$DOMAIN/ didn't serve $VERSION" >&2
exit 1
