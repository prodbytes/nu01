#!/usr/bin/env bash
# Deploys the nu01-log-retention stack (infra/log-retention.yaml): a Lambda
# function that runs daily and caps every log group in the account and
# region to a 14-day retention, so log events older than two weeks are
# deleted by CloudWatch.
#
# Run by hand with admin credentials; CI doesn't deploy it (the GitHub
# deploy roles may touch only the site stacks).
# Settings, from the environment:
#   RETENTION_DAYS  default 14
#   AWS_REGION      default us-east-1
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

# Tagged for cost allocation (CloudFormation copies the stack's tags to its
# resources)
echo "==> deploying nu01-log-retention ($AWS_REGION)"
aws cloudformation deploy --stack-name nu01-log-retention --template-file infra/log-retention.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides "RetentionDays=${RETENTION_DAYS:-14}" \
  --tags project=nu01 tenancy=shared \
  --no-fail-on-empty-changeset

echo "==> running it once"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
aws lambda invoke --function-name nu01-log-retention --log-type Tail \
  --query LogResult --output text "$out" | base64 --decode | grep -E '^(set|FAIL|[0-9]+ log groups)' || true
if grep -q errorMessage "$out"; then
  echo "error: $(cat "$out")" >&2
  exit 1
fi
