#!/usr/bin/env bash
# Deploys the nu01.com DNS stacks, in order:
#   nu01-route53-zone   infra/zone.yaml   the nu01.com hosted zone
#   nu01-route53-gmail  infra/gmail.yaml  Google Workspace MX and SPF
#   nu01-dns            infra/dns.yaml    the apps' records merged from their
#                                         old subzones (Migrate<Project>)
# The first two came from prodbytes/dsp unchanged (same parameters), so a
# redeploy only adds the stack tags. Run by hand with admin credentials; CI
# doesn't deploy them.
#
#   scripts/deploy-dns.sh [Key=Value ...]
# Key=Value pairs are passed to nu01-dns, e.g. GrigriDistribution=dxyz.cloudfront.net
# for a changed distribution: parameters not passed keep their current
# value (or the template default on a first deploy). scripts/migrate-subzone.sh
# sets the Migrate<Project> switches; don't flip them by hand.
# Settings, from the environment:
#   STACKS      which to deploy (default: "zone gmail dns")
#   AWS_REGION  default us-east-1 (the zone's exports must be there)
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
STACKS="${STACKS:-zone gmail dns}"

# deploy <stack> <template> [Key=Value ...]: tagged for cost allocation
# (CloudFormation copies the stack's tags to its resources)
deploy() {
  local stack="$1" template="$2"
  shift 2
  echo "==> deploying $stack"
  aws cloudformation deploy --stack-name "$stack" --template-file "$template" \
    ${1+--parameter-overrides "$@"} \
    --tags project=nu01 tenancy=shared \
    --no-fail-on-empty-changeset
}

for s in $STACKS; do
  case "$s" in
    zone) deploy nu01-route53-zone infra/zone.yaml TenantId=nu01 DomainName=nu01.com ;;
    gmail) deploy nu01-route53-gmail infra/gmail.yaml TenantId=nu01 ;;
    dns) deploy nu01-dns infra/dns.yaml "$@" ;;
    *) echo "error: unknown stack '$s' (zone, gmail or dns)" >&2; exit 2 ;;
  esac
done
