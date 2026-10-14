#!/usr/bin/env bash
# Merges one app's delegated subzone (grigri., tabscan., rbacr. or
# uplink.nu01.com) into the nu01.com zone, without downtime and without
# deleting anything that resolvers may still use. Admin-run, by hand.
#
#   scripts/migrate-subzone.sh <grigri|tabscan|rbacr|uplink>
#
# Without CONFIRM=yes (the default, a dry run) it only reads: it checks the
# subzone holds exactly the records nu01-dns will recreate, prints the
# change batches, and digs the nu01.com name servers. With CONFIRM=yes:
#   a. lowers nu01.com's SOA negative-caching TTL (its last field) to 60 s,
#      once, so a resolver that asks during the switch caches "no such
#      name" for a minute at most, not 15;
#   b. in ONE atomic change batch on nu01.com: deletes the <project>.nu01.com
#      NS delegation and upserts copies of the subzone's ACM validation
#      CNAMEs (_*), so certificate renewals keep validating;
#   c. right away deploys nu01-dns with Migrate<Project>=true (the other
#      projects keep their current switch) and this project's distributions
#      as the subzone has them, so the aliases exist in nu01.com within
#      seconds. If that deploy fails, it restores the NS delegation;
#   d. checks every name answers authoritatively from each nu01.com name
#      server, and that each https://<host>/ answers at the address nu01.com
#      gives.
# The NS record must go before the records are created: a delegation point
# may hold only NS (and DS) in the parent (Route 53 is reported to refuse
# others), and while it exists nothing at or below it in nu01.com is served
# (see specs/dns.md).
#
# It never deletes the subzone or its records: resolvers that cached the
# subzone's own NS record keep asking it for up to that record's TTL
# (172800 s). It prints when the project's round 2 (its stacks stop writing
# to the subzone) and the subzone deletion may happen, and how.
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
APEX_ZONE=Z04838091YTBIM6PNI1XK
go="${CONFIRM:-}"
project="${1:-}"

# Per project: its subzone, the stack that owns the NS delegation in nu01.com
# (none: made by hand), its hosts and the nu01-dns parameter holding each
# one's distribution, and its other records ("name type ttl value[|value]").
case "$project" in
  grigri)
    SUBZONE=Z087054988V7QH92N1FX; PARAM=MigrateGrigri; NS_STACK=
    HOSTS="grigri.nu01.com=GrigriDistribution rc.grigri.nu01.com=GrigriRcDistribution"
    OTHERS="local.grigri.nu01.com. A 3600 127.0.0.1
local.grigri.nu01.com. AAAA 3600 ::1" ;;
  tabscan)
    SUBZONE=Z10277161AEN9OU2H73PJ; PARAM=MigrateTabscan; NS_STACK=
    HOSTS="tabscan.nu01.com=TabscanDistribution rc.tabscan.nu01.com=TabscanRcDistribution"
    OTHERS="local.tabscan.nu01.com. A 300 127.0.0.1
local.tabscan.nu01.com. AAAA 300 ::1" ;;
  rbacr)
    SUBZONE=Z0415297342E0C595290P; PARAM=MigrateRbacr; NS_STACK=rbacr-zone
    HOSTS="rbacr.nu01.com=RbacrDistribution rc.rbacr.nu01.com=RbacrRcDistribution"
    OTHERS="local.rbacr.nu01.com. A 3600 127.0.0.1
rbacr.nu01.com. CAA 3600 0 issue \"amazon.com\"|0 issuewild \";\"" ;;
  uplink)
    SUBZONE=Z04348662JLR2LAZSOI74; PARAM=MigrateUplink; NS_STACK=uplink-zone
    HOSTS="uplink.nu01.com=UplinkDistribution rc.uplink.nu01.com=UplinkRcDistribution sh.uplink.nu01.com=UplinkShDistribution"
    OTHERS="" ;;
  *) echo "usage: $0 <grigri|tabscan|rbacr|uplink>" >&2; exit 2 ;;
esac
DOMAIN="$project.nu01.com"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fmt_time() { # fmt_time <epoch seconds>: UTC, on macOS and Linux
  date -u -r "$1" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || date -u -d "@$1" '+%Y-%m-%d %H:%M UTC'
}
wait_change() { # wait_change <change id>
  echo "    waiting for $1 to be INSYNC"
  aws route53 wait resource-record-sets-changed --id "$1"
}

# ---- Read the current state (read-only)
echo "==> reading $DOMAIN ($SUBZONE) and nu01.com ($APEX_ZONE)"
aws route53 list-resource-record-sets --hosted-zone-id "$SUBZONE" --output json >"$work/sub.json"
aws route53 list-resource-record-sets --hosted-zone-id "$APEX_ZONE" --output json >"$work/apex.json"
apex_ns="$(aws route53 get-hosted-zone --id "$APEX_ZONE" \
  --query 'DelegationSet.NameServers' --output text)"
migrated_params="$(aws cloudformation describe-stacks --stack-name nu01-dns \
  --query 'Stacks[0].Parameters[?starts_with(ParameterKey, `Migrate`)].[ParameterKey,ParameterValue]' \
  --output text 2>/dev/null || true)"

# The plan, worked out in Python from the two zones: checks, the change
# batches (main, rollback) and the facts the rest of the script uses.
export DOMAIN HOSTS OTHERS work
python3 - <<'PY'
import json, os, sys
d = os.environ["DOMAIN"] + "."
work = os.environ["work"]
sub = json.load(open(f"{work}/sub.json"))["ResourceRecordSets"]
apex = json.load(open(f"{work}/apex.json"))["ResourceRecordSets"]
hosts = [h.split("=") for h in os.environ["HOSTS"].split()]
def under(name):  # at or below the project's name
    return name == d or name.endswith("." + d)
def show(r):
    if "AliasTarget" in r:
        return f"{r['Name']} {r['Type']} alias {r['AliasTarget']['DNSName']}"
    return f"{r['Name']} {r['Type']} {r.get('TTL')} " + "|".join(v["Value"] for v in r["ResourceRecords"])

errors, facts = [], {}
# Subzone: aliases (A and AAAA per host, to CloudFront), validation CNAMEs,
# and exactly the expected others; nothing else.
expected_alias = {(h + ".", t) for h, _ in hosts for t in ("A", "AAAA")}
expected_other = set(filter(None, os.environ["OTHERS"].split("\n")))
cnames, dist = [], {}
for r in sub:
    if r["Name"] == d and r["Type"] in ("NS", "SOA"):
        if r["Type"] == "NS":
            facts["SUB_NS_TTL"] = r["TTL"]
        continue
    if r["Name"].startswith("_") and r["Type"] == "CNAME":
        cnames.append(r)
    elif "AliasTarget" in r and (r["Name"], r["Type"]) in expected_alias:
        if r["AliasTarget"]["HostedZoneId"] != "Z2FDTNDATAQYW2":
            errors.append(f"not a CloudFront alias: {show(r)}")
        dist.setdefault(r["Name"], set()).add(r["AliasTarget"]["DNSName"].rstrip("."))
        expected_alias.discard((r["Name"], r["Type"]))
    elif show(r) in expected_other:
        expected_other.discard(show(r))
    else:
        errors.append(f"subzone record nu01-dns doesn't hold: {show(r)}")
errors += [f"missing in subzone: {n} {t}" for n, t in sorted(expected_alias)]
errors += [f"missing in subzone: {o}" for o in sorted(expected_other)]
overrides = []
for h, param in hosts:
    targets = dist.get(h + ".", set())
    if len(targets) != 1:
        errors.append(f"{h}: A and AAAA don't share one distribution: {targets}")
    else:
        overrides.append(f"{param}={targets.pop()}")

# nu01.com: the delegation, and nothing else at or below the name except
# our own earlier copies of the validation CNAMEs or nu01-dns's records.
ns = [r for r in apex if r["Name"] == d and r["Type"] == "NS"]
copies = {r["Name"] for r in cnames}
others = [r for r in apex if under(r["Name"]) and r not in ns and r["Name"] not in copies]
soa = next(r for r in apex if r["Type"] == "SOA")
fields = soa["ResourceRecords"][0]["Value"].split()
facts["SOA_MIN"] = fields[6]
facts["APEX_NS_TTL"] = ns[0]["TTL"] if ns else 0
facts["NS_PRESENT"] = "yes" if ns else "no"
facts["APEX_OTHERS"] = len(others)
fields[6] = "60"
json.dump({"Comment": "nu01.com: negative-caching TTL 60 s (subzone migration)",
           "Changes": [{"Action": "UPSERT", "ResourceRecordSet": dict(soa, ResourceRecords=[{"Value": " ".join(fields)}])}]},
          open(f"{work}/soa.json", "w"), indent=1)
new_copies = [r for r in cnames if not any(a["Name"] == r["Name"] for a in apex)]
changes = [{"Action": "DELETE", "ResourceRecordSet": r} for r in ns]
changes += [{"Action": "UPSERT", "ResourceRecordSet": r} for r in cnames]
json.dump({"Comment": f"Merge {d} into nu01.com: drop the delegation, copy ACM validation",
           "Changes": changes}, open(f"{work}/main.json", "w"), indent=1)
with open(f"{work}/main.txt", "w") as f:
    for c in changes:
        f.write(f"{c['Action']} {show(c['ResourceRecordSet'])}\n")
with open(f"{work}/cnames.txt", "w") as f:
    for r in cnames:
        f.write(f"{r['Name']} CNAME\n")
rollback = [{"Action": "DELETE", "ResourceRecordSet": r} for r in new_copies]
rollback += [{"Action": "CREATE", "ResourceRecordSet": r} for r in ns]
json.dump({"Comment": f"Restore the {d} delegation", "Changes": rollback},
          open(f"{work}/rollback.json", "w"), indent=1)

print("    subzone records:")
for r in sub:
    print("      " + show(r))
if others:
    print("    already in nu01.com at or below the name:")
    for r in others:
        print("      " + show(r))
with open(f"{work}/facts", "w") as f:
    for k, v in facts.items():
        f.write(f"{k}={v}\n")
open(f"{work}/overrides", "w").write("\n".join(overrides) + "\n")
if errors:
    print("error: the subzone isn't what nu01-dns recreates; update infra/dns.yaml "
          "and this script first:\n  " + "\n  ".join(errors), file=sys.stderr)
    sys.exit(1)
PY
# shellcheck disable=SC1091
source "$work/facts"
overrides=()
while IFS= read -r line; do [[ -n "$line" ]] && overrides+=("$line"); done <"$work/overrides"

current_switch() { # current_switch <MigrateX>: its value in nu01-dns (default false)
  awk -v k="$1" '$1 == k { v = $2 } END { print (v == "" ? "false" : v) }' <<<"$migrated_params"
}
for p in MigrateGrigri MigrateTabscan MigrateRbacr MigrateUplink; do
  if [[ "$p" == "$PARAM" ]]; then overrides+=("$p=true"); else overrides+=("$p=$(current_switch "$p")"); fi
done
already="$(current_switch "$PARAM")"

if [[ "$NS_PRESENT" == no && "$already" != true && "$APEX_OTHERS" != 0 ]]; then
  echo "error: $DOMAIN isn't delegated, nu01-dns doesn't hold it, but nu01.com has records for it" >&2
  exit 1
fi
if [[ "$NS_PRESENT" == yes && "$APEX_OTHERS" != 0 ]]; then
  echo "error: nu01.com has records at or below the $DOMAIN delegation; remove them first" >&2
  exit 1
fi

echo "==> state: delegation in nu01.com: $NS_PRESENT (TTL $APEX_NS_TTL s), nu01-dns $PARAM=$already"
echo "    subzone NS TTL: $SUB_NS_TTL s; nu01.com SOA minimum: $SOA_MIN s (negative answers"
echo "    are cached for the lesser of it and the SOA record's TTL, 900 s)"
if [[ -n "$NS_STACK" && "$NS_PRESENT" == yes ]]; then
  owner="$(aws cloudformation describe-stack-resource --stack-name "$NS_STACK" \
    --logical-resource-id Delegation --query StackResourceDetail.ResourceStatus \
    --output text 2>/dev/null || echo 'not found')"
  echo "    the delegation belongs to stack $NS_STACK (resource Delegation: $owner): deleting it here"
  echo "    drifts that stack; never update it again, delete it in round 2 (see the end)"
fi

echo "==> (a) SOA: minimum (negative-caching TTL) $SOA_MIN -> 60"
[[ "$SOA_MIN" -le 60 ]] && echo "    already $SOA_MIN; nothing to do"
echo "==> (b) one change batch on nu01.com:"
sed 's/^/    /' "$work/main.txt"
echo "==> (c) deploy nu01-dns: ${overrides[*]}"

check_names() { # check_names strict|report: dig every name at each nu01.com
  # name server (strict: all four, quiet when fine; report: the first one)
  local ok=0 ns name type out flags servers="$apex_ns"
  [[ "$1" == strict ]] || servers="${apex_ns%%[[:space:]]*}"
  for ns in $servers; do
    for name in $(sed 's/=[^ ]*//g' <<<"$HOSTS"); do
      for type in A AAAA; do
        out="$(dig +norec +time=3 +tries=2 "@$ns" "$name" "$type")"
        flags="$(grep -m1 'flags:' <<<"$out")"
        if [[ "$flags" == *" aa"* ]] && grep -q "^$name\.[[:space:]].*IN[[:space:]]$type" <<<"$out"; then
          [[ "$1" == strict ]] || echo "    $ns $name $type: answered from nu01.com"
        else
          echo "    $ns $name $type: not answered from nu01.com$(grep -q 'AUTHORITY: [1-9]' <<<"$out" && grep -q "IN[[:space:]]NS" <<<"$out" && echo ' (still a referral to the subzone)')"
          ok=1
        fi
      done
    done
    while IFS=' ' read -r name type _; do
      [[ -n "$name" ]] || continue
      if [[ -z "$(dig +norec +short +time=3 +tries=2 "@$ns" "${name%.}" "$type")" ]]; then
        echo "    $ns ${name%.} $type: no answer"; ok=1
      fi
    done < <(printf '%s\n' "$OTHERS"; cat "$work/cnames.txt")
  done
  return $ok
}
check_https() { # each host answers HTTPS at the address nu01.com's first name server gives
  local ok=0 ns name ip code
  ns="${apex_ns%%[[:space:]]*}"
  for name in $(sed 's/=[^ ]*//g' <<<"$HOSTS"); do
    ip="$(dig +norec +short +time=3 "@$ns" "$name" A | grep -E '^[0-9.]+$' | head -1 || true)"
    if [[ -n "$ip" ]]; then
      code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --resolve "$name:443:$ip" "https://$name/" || true)"
    else
      code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "https://$name/" || true)"
      ip="(public DNS)"
    fi
    echo "    https://$name/ at $ip: HTTP ${code:-none}"
    [[ "$code" =~ ^[234][0-9][0-9]$ ]] || ok=1
  done
  return $ok
}

if [[ "$go" != yes ]]; then
  echo "==> (d) now, from the nu01.com name servers (dry run: referrals are expected before the migration)"
  check_names report || true
  check_https || true
  echo "==> dry run; CONFIRM=yes $0 $project applies (a) to (d)"
  echo "    change batch: $(cat "$work/main.json" | tr -s ' \n' ' ')"
  exit 0
fi

# ---- Apply
if [[ "$SOA_MIN" -gt 60 ]]; then
  echo "==> (a) lowering the SOA negative-caching TTL"
  wait_change "$(aws route53 change-resource-record-sets --hosted-zone-id "$APEX_ZONE" \
    --change-batch "file://$work/soa.json" --query ChangeInfo.Id --output text)"
fi
started="$(date +%s)"
if python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["Changes"] else 1)' "$work/main.json"; then
  echo "==> (b) applying the change batch"
  wait_change "$(aws route53 change-resource-record-sets --hosted-zone-id "$APEX_ZONE" \
    --change-batch "file://$work/main.json" --query ChangeInfo.Id --output text)"
fi
echo "==> (c) deploying nu01-dns"
if ! STACKS=dns bash scripts/deploy-dns.sh "${overrides[@]}"; then
  if [[ "$NS_PRESENT" == yes ]]; then
    echo "==> nu01-dns failed: restoring the $DOMAIN delegation" >&2
    aws route53 change-resource-record-sets --hosted-zone-id "$APEX_ZONE" \
      --change-batch "file://$work/rollback.json" --query ChangeInfo.Id --output text >&2
  fi
  exit 1
fi
echo "==> (d) checking"
for attempt in $(seq 1 12); do
  if check_names strict; then break; fi
  [[ "$attempt" == 12 ]] && { echo "error: names not served from nu01.com after 2 minutes" >&2; exit 1; }
  echo "    not yet (attempt $attempt/12); retrying in 10 s"; sleep 10
done
check_names report
check_https || { echo "error: a host doesn't answer HTTPS" >&2; exit 1; }

# ---- Round 2
ready=$(( started + SUB_NS_TTL + 3600 ))
echo "==> $DOMAIN now resolves from nu01.com."
echo "    Until $(fmt_time "$ready") (the subzone NS TTL, $SUB_NS_TTL s, plus an hour),"
echo "    resolvers may still ask the subzone: leave it and its records alone."
echo "    After that, round 2 and the deletion (see specs/dns.md):"
echo "      1. the $project repo's stacks stop writing records to $SUBZONE and"
echo "         validate their certificates in nu01.com ($APEX_ZONE)"
case "$project" in
  grigri|tabscan)
    echo "      2. empty the hand-made zone and delete it:"
    echo "         aws route53 list-resource-record-sets --hosted-zone-id $SUBZONE --output json \\"
    echo "           | python3 -c 'import json,sys; print(json.dumps({\"Changes\": [{\"Action\": \"DELETE\", \"ResourceRecordSet\": r} for r in json.load(sys.stdin)[\"ResourceRecordSets\"] if r[\"Type\"] not in (\"NS\", \"SOA\")]}))' >empty.json"
    echo "         aws route53 change-resource-record-sets --hosted-zone-id $SUBZONE --change-batch file://empty.json"
    echo "         aws route53 delete-hosted-zone --id $SUBZONE" ;;
  rbacr|uplink)
    echo "      2. once no stack imports or uses the zone (uplink: uplink-web, uplink-rc-web,"
    echo "         uplink-sh, uplink-acm-cert, uplink-rc-acm-cert, uplink-github-deploy import"
    echo "         uplink-zone-HostedZoneId), delete records no stack owns, then the zone stack:"
    echo "         aws route53 list-resource-record-sets --hosted-zone-id $SUBZONE   # leftovers"
    echo "         aws cloudformation delete-stack --stack-name $NS_STACK"
    echo "         # Delegation is gone already: if the delete fails on it, run"
    echo "         aws cloudformation delete-stack --stack-name $NS_STACK --retain-resources Delegation" ;;
esac
