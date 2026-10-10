#!/usr/bin/env bash
# Removes what served https://nu01.com before this repository (a CloudFront
# distribution in front of S3 that redirects to prodbytes.substack.com), so
# the nu01-web stack can take the nu01.com alias and records. Run it once,
# by hand with admin credentials, right before the first GA deploy: the
# apex is down from here until that deploy finishes.
#
# Without CONFIRM=yes it only prints what it found and would delete.
# With it, for each distribution whose aliases include nu01.com (other than
# the nu01-web stack's):
#   - if a CloudFormation stack owns it, deletes that stack;
#   - otherwise backs up its S3 origin buckets to legacy-backup/<bucket>/,
#     deletes the nu01.com A/AAAA records, disables and deletes the
#     distribution, then empties and deletes the buckets, and deletes its
#     ACM certificate.
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
DOMAIN=nu01.com
go="${CONFIRM:-}"

run() { # prints, and runs only with CONFIRM=yes
  echo "    + $*"
  if [[ "$go" == yes ]]; then "$@"; fi
}

zone="$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN" --max-items 1 \
  --query "HostedZones[?Name=='$DOMAIN.' && !Config.PrivateZone].Id | [0]" --output text)"
zone="${zone#/hostedzone/}"
echo "==> zone $DOMAIN: $zone"

ours="$(aws cloudformation describe-stacks --stack-name nu01-web \
  --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" --output text 2>/dev/null || true)"

mapfile -t ids < <(aws cloudfront list-distributions --output text \
  --query "DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '$DOMAIN')].Id")
ids=("${ids[@]//[[:space:]]/}")
found=0
for id in ${ids[@]+"${ids[@]}"}; do
  [[ -z "$id" || "$id" == "$ours" ]] && continue
  found=1
  arn="$(aws cloudfront get-distribution --id "$id" --query Distribution.ARN --output text)"
  stack="$(aws cloudfront list-tags-for-resource --resource "$arn" \
    --query "Tags.Items[?Key=='aws:cloudformation:stack-name'].Value | [0]" --output text)"
  echo "==> legacy distribution $id"
  aws cloudfront get-distribution-config --id "$id" \
    --query 'DistributionConfig.{Aliases:Aliases.Items,Origins:Origins.Items[].DomainName,Certificate:ViewerCertificate.ACMCertificateArn,Comment:Comment}'

  if [[ -n "$stack" && "$stack" != None ]]; then
    echo "    owned by stack $stack: deleting the stack"
    run aws cloudformation delete-stack --stack-name "$stack"
    run aws cloudformation wait stack-delete-complete --stack-name "$stack"
    continue
  fi

  cert="$(aws cloudfront get-distribution-config --id "$id" \
    --query DistributionConfig.ViewerCertificate.ACMCertificateArn --output text)"
  # S3 origins: bucket.s3.<region>.amazonaws.com, bucket.s3.amazonaws.com,
  # or a website endpoint, bucket.s3-website[-.]<region>.amazonaws.com.
  mapfile -t buckets < <(aws cloudfront get-distribution-config --id "$id" \
    --query 'DistributionConfig.Origins.Items[].DomainName' --output text | tr '\t' '\n' |
    sed -nE 's/^(.+)\.s3([.-]website)?[.-]([a-z0-9-]+\.)?amazonaws\.com$/\1/p')

  for bucket in ${buckets[@]+"${buckets[@]}"}; do
    echo "    origin bucket $bucket: backing up to legacy-backup/$bucket/"
    run aws s3 sync "s3://$bucket/" "legacy-backup/$bucket/" --only-show-errors
    if [[ "$go" == yes ]]; then
      aws s3api get-bucket-website --bucket "$bucket" --output json \
        > "legacy-backup/$bucket.website.json" 2>/dev/null || true
    fi
  done

  for type in A AAAA; do
    record="$(aws route53 list-resource-record-sets --hosted-zone-id "$zone" \
      --query "ResourceRecordSets[?Name=='$DOMAIN.' && Type=='$type'] | [0]" --output json)"
    if [[ "$record" != null ]]; then
      echo "    deleting the $DOMAIN $type record"
      run aws route53 change-resource-record-sets --hosted-zone-id "$zone" \
        --change-batch "{\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":$record}]}"
    fi
  done

  echo "    disabling, then deleting, the distribution"
  if [[ "$go" == yes ]]; then
    tmp="$(mktemp)"
    etag="$(aws cloudfront get-distribution-config --id "$id" --query ETag --output text)"
    aws cloudfront get-distribution-config --id "$id" --query DistributionConfig --output json |
      python3 -c 'import json,sys; c=json.load(sys.stdin); c["Enabled"]=False; c["Aliases"]={"Quantity":0}; json.dump(c,sys.stdout)' > "$tmp"
    aws cloudfront update-distribution --id "$id" --if-match "$etag" \
      --distribution-config "file://$tmp" > /dev/null
    rm -f "$tmp"
    aws cloudfront wait distribution-deployed --id "$id"
    etag="$(aws cloudfront get-distribution-config --id "$id" --query ETag --output text)"
    aws cloudfront delete-distribution --id "$id" --if-match "$etag"
  fi

  for bucket in ${buckets[@]+"${buckets[@]}"}; do
    echo "    deleting bucket $bucket"
    run aws s3 rb "s3://$bucket" --force
  done
  if [[ -n "$cert" && "$cert" != None ]]; then
    echo "    deleting certificate $cert"
    run aws acm delete-certificate --certificate-arn "$cert"
  fi
done

if [[ "$found" == 0 ]]; then
  echo "==> no legacy distribution has the $DOMAIN alias; nothing to do"
elif [[ "$go" != yes ]]; then
  echo "==> dry run: nothing changed. Run again with CONFIRM=yes to delete the above."
else
  echo "==> legacy resources removed; deploy GA now (scripts/release-ga.sh)"
fi
