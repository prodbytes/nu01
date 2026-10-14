#!/usr/bin/env bash
# Deploys the nu01-monitor stack (infra/monitor.yaml): a Lambda function
# that checks every nu01 app endpoint, GA and RC, every 5 minutes, and an
# alarm that emails the nu01-health topic when checks fail. It replaced the
# per-project Route 53 health checks.
#
# Run by hand with admin credentials; CI doesn't deploy it (the GitHub
# deploy roles may touch only the site stacks). After the first deploy,
# confirm the subscription email sent to ALERT_EMAIL.
# Settings, from the environment:
#   ALERT_EMAIL  default: the template's (julio+health@nu01.com)
#   AWS_REGION   default us-east-1
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

overrides=()
[[ -n "${ALERT_EMAIL:-}" ]] && overrides=(--parameter-overrides "AlertEmail=$ALERT_EMAIL")

# Tagged for cost allocation (CloudFormation copies the stack's tags to its
# resources)
echo "==> deploying nu01-monitor ($AWS_REGION)"
aws cloudformation deploy --stack-name nu01-monitor --template-file infra/monitor.yaml \
  --capabilities CAPABILITY_IAM \
  ${overrides[@]+"${overrides[@]}"} \
  --tags project=nu01 tenancy=shared \
  --no-fail-on-empty-changeset

echo "==> running it once"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
aws lambda invoke --function-name nu01-monitor --log-type Tail \
  --query LogResult --output text "$out" | base64 --decode | grep -E '^(ok|FAIL) ' || true
if grep -q errorMessage "$out"; then
  echo "error: $(cat "$out")" >&2
  exit 1
fi
echo "==> all endpoints healthy"
