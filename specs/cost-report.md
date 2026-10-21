# Cost report

[scripts/cost-report.py](../scripts/cost-report.py) (`make cost`, `devbox
run cost`) reports AWS cost from Cost Explorer (unblended, USD).

- **By profile:** it reads every AWS CLI profile (`aws configure
  list-profiles`, or `--profiles`), reports each account once (`default` and
  `nu01` are the same account), and lists the profiles it can't read with
  the reason (no credentials, an expired SSO login, an invalid key). It never
  waits for input: no MFA or SSO prompts, and a 60 s limit per call.
- **By month:** the current month to date and the 3 previous months
  (`--months`): usage per project, then credits, refunds and tax, then the
  net total, and the forecast for the rest of the month.
- **By day:** the last 14 days (`--days`), the same split.
- **By service:** this month's usage per project, by service.
- **Projects** are the `project` cost allocation tag that every nu01 stack
  carries (activated, and backfilled to 2025-11). Old names fold into new
  ones (`tabscan` counts as `tabcam`). Costs from before the stacks were
  tagged (2026-10-14), and costs that can't carry a tag (Route 53 domain
  renewals, hosted-zone fees billed at the start of the month), show as
  "(untagged)".
- **Files:** `reports/costs/YYYY/MM/cost-report-YYYYMMDD-HHMMSSZ.md` and a
  `.json` with the same numbers (UTC time stamps). git ignores `reports/`:
  the repository is public.
- **Cost:** each Cost Explorer request costs $0.01; a report makes four per
  readable account.
