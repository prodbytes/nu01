# DNS

This repository owns the shared nu01 infrastructure: the `nu01.com` zone,
its mail records, the apps' records in it, and the uptime monitor
([monitor.md](monitor.md)). Each is a stack tagged `project=nu01`,
`tenancy=shared`, deployed by hand with admin credentials (CI's roles can't).

| Stack | Template | Holds | Deployed by |
|---|---|---|---|
| `nu01-route53-zone` | [infra/zone.yaml](../infra/zone.yaml) | The `nu01.com` hosted zone (`Z04838091YTBIM6PNI1XK`), exports `nu01-HostedZoneId`, `nu01-HostedZoneName`, `nu01-NameServers` | [scripts/deploy-dns.sh](../scripts/deploy-dns.sh) |
| `nu01-route53-gmail` | [infra/gmail.yaml](../infra/gmail.yaml) | Google Workspace MX (`1 smtp.google.com`) and SPF; DKIM is added by hand | deploy-dns.sh |
| `nu01-dns` | [infra/dns.yaml](../infra/dns.yaml) | The apps' records moved in from their subzones, one `Migrate<Project>` switch each | deploy-dns.sh, [scripts/migrate-subzone.sh](../scripts/migrate-subzone.sh) |
| `nu01-monitor` | [infra/monitor.yaml](../infra/monitor.yaml) | Uptime checks | [scripts/deploy-monitor.sh](../scripts/deploy-monitor.sh) |

The zone and gmail stacks were made by prodbytes/dsp
(`gitops/nu01/nu01-deploy.sh`); their templates here are the deployed ones
with new header comments, deployed with the same parameters
(`TenantId=nu01 DomainName=nu01.com`, `TenantId=nu01`), so a redeploy only
adds the stack tags. The nu01.com and rc.nu01.com site records belong to
`nu01-web` and `nu01-rc-web` ([deploy.md](deploy.md)); presence's records
belong to its own stacks.

## Merging the app subzones

grigri., tabscan., rbacr. and uplink.nu01.com were each a delegated hosted
zone ($0.50/month each). `nu01-dns` recreates their records in `nu01.com`,
one project at a time:

| Project | Subzone | Delegation (NS in nu01.com) made by | nu01-dns recreates | ACM validation CNAMEs copied |
|---|---|---|---|---|
| grigri | `Z087054988V7QH92N1FX` | hand | grigri., rc.grigri. (A/AAAA aliases); local.grigri. A 127.0.0.1, AAAA ::1 (3600 s) | 2 |
| tabscan | `Z10277161AEN9OU2H73PJ` | hand | tabscan., rc.tabscan. (A/AAAA); local.tabscan. A, AAAA (300 s) | 2 |
| rbacr | `Z0415297342E0C595290P` | stack `rbacr-zone` (`Delegation`) | rbacr., rc.rbacr. (A/AAAA); local.rbacr. A (3600 s); CAA `0 issue "amazon.com"`, `0 issuewild ";"` | 2 |
| uplink | `Z04348662JLR2LAZSOI74` | stack `uplink-zone` (`Delegation`) | uplink., rc.uplink., sh.uplink. (A/AAAA) | 3 |

The aliases point at CloudFront (`Z2FDTNDATAQYW2`); each distribution's
domain is a parameter of `nu01-dns`. TTLs: the delegations in nu01.com are
3600 s, the subzones' own NS records 172800 s (48 h), nu01.com's SOA record
900 s with a minimum of 86400 s.

### Why this order

A name with an NS record in the parent is a delegation point: in the parent
zone it may hold only NS (and DS) records, and nothing at or below it is
served from the parent while the NS record exists (RFC 1034 §4.2.1; the
parent answers with a referral). AWS's docs don't say whether Route 53
accepts other record types beside a delegation NS record (it is reported to
refuse them as conflicting; not tested here, since that takes a write);
either way they would not be served. So the NS record goes first and the
records follow, never the other way round.

### Round 1: `scripts/migrate-subzone.sh <project>`

A dry run (the default) reads both zones, refuses to go on if the subzone
holds anything `nu01-dns` doesn't recreate, prints the change batch and
digs nu01.com's name servers. `CONFIRM=yes` applies:

1. **SOA**, once: nu01.com's negative-caching TTL (the SOA minimum, its
   last field) goes from 86400 to 60, keeping the other fields. Negative
   answers are cached for the lesser of that and the SOA record's TTL (900
   s), so a resolver that asks in the seconds between steps 2 and 3
   remembers "no such name" for a minute instead of 15.
2. **One atomic change batch** on nu01.com: delete the `<project>.nu01.com`
   NS record and upsert copies of the subzone's ACM validation CNAMEs (names
   starting with `_`), so the certificates keep renewing whichever zone a
   resolver asks.
3. **Deploy `nu01-dns`** with `Migrate<Project>=true`, the other projects'
   switches as they are, and the distributions the subzone points at. If
   the deploy fails, the script restores the NS record.
4. **Check** that every name gets an authoritative answer from all four
   nu01.com name servers, and that each `https://<host>/` answers at the
   address nu01.com gives.

Resolvers that cached the delegation keep using the subzone, which still
answers the same, so they see nothing change; only a resolver with nothing
cached can hit the gap of step 2 to 3 (seconds).

For rbacr and uplink, step 2 deletes a record their zone stack owns. That
stack drifts: don't update it again (a changed `Delegation` would put the
NS back and hide the records); delete it in round 2.

### Waiting

Resolvers may keep the subzone's NS record (172800 s) and keep asking the
subzone directly, so the subzone and its records stay untouched for **48
hours after step 2, plus an hour of margin**. The script prints that time.
Example: a migration at 2026-10-15 10:00 UTC allows round 2 from 2026-10-17
11:00 UTC.

### Round 2 (in each project's repository), then the deletion

1. The project's stacks stop writing their A/AAAA records to the subzone
   (`nu01-dns` holds them) and validate their certificates in nu01.com. A
   certificate whose validation zone changes is replaced; its stack then
   creates the new validation CNAME in nu01.com itself. Delete the copied
   CNAMEs once no certificate uses them.
2. Delete the subzone:
   - grigri, tabscan (made by hand): delete its remaining records except NS
     and SOA, then `aws route53 delete-hosted-zone --id <zone>` (the script
     prints the exact commands).
   - rbacr: `aws cloudformation delete-stack --stack-name rbacr-zone` once
     the rbacr stacks no longer use the zone; delete leftover records no
     stack owns first.
   - uplink: first remove the imports of `uplink-zone-HostedZoneId`
     (uplink-web, uplink-rc-web, uplink-sh, uplink-acm-cert,
     uplink-rc-acm-cert, uplink-github-deploy), then delete `uplink-zone`.
   - If a zone stack's delete fails on its already-deleted `Delegation`,
     run it again with `--retain-resources Delegation`.

## Adding a host

For a new name under a migrated app, add a record (and, for an alias, a
`<Name>Distribution` parameter) to that project's record group in
[infra/dns.yaml](../infra/dns.yaml) and run `scripts/deploy-dns.sh`. A new
parameter takes its default; to change an existing distribution, pass it
(`scripts/deploy-dns.sh UplinkDistribution=dxyz.cloudfront.net`), since a
stack update keeps a parameter's previous value. A site that owns its own
records (like nu01-web) can instead create them in `nu01.com` from its own
stack.
