# Monitor

The `nu01-monitor` stack ([infra/monitor.yaml](../infra/monitor.yaml),
deployed by hand with [scripts/deploy-monitor.sh](../scripts/deploy-monitor.sh))
watches every nu01 app, GA and RC. It replaced the per-project Route 53
health checks (14 of them, about $24/month for their HTTPS and
string-match options).

- **Checks:** a Lambda function (`nu01-monitor`, Python, arm64, 128 MB),
  run every 5 minutes by an EventBridge rule, fetches each endpoint over
  HTTPS (10 s timeout, one retry 3 s later). An endpoint is healthy when it
  answers 2xx (redirects followed) and, if it has a `match`, its body
  contains that string. Logs go to `/aws/lambda/nu01-monitor` (14 days).
- **Failing:** the run fails (raises) and logs each failing URL with its
  status or error. The alarm `nu01-monitor-errors` (Errors >= 1 in 2
  consecutive 5-minute periods; no data, i.e. the function didn't run,
  counts as failing) emails the `nu01-health` SNS topic on ALARM and on OK.
  A failing run also emails the list of failing URLs, unless the alarm is
  already in ALARM, so an outage isn't an email every 5 minutes.
- **Email:** `AlertEmail` (default `julio+health@nu01.com`); confirm the
  subscription email after the first deploy.
- **Endpoints:** the `Endpoints` parameter, one JSON object per line. To add
  one, add a line and run `scripts/deploy-monitor.sh`:

  ```json
  {"url": "https://example.nu01.com/health", "match": "\"status\":\"ok\""},
  ```

  | App | Path (GA and `rc.` host) | Body must contain |
  |---|---|---|
  | presence.nu01.com | `/health` | `"status":"ok"` |
  | grigri.nu01.com | `/app/version.json` | `"app_name":"grigri_app"` |
  | grigri.nu01.com | `/api/health` | `"ok":true` |
  | tabscan.nu01.com | `/app/version.json` | `"app_name":"tabscan_app"` |
  | rbacr.nu01.com | `/health` | (2xx only) |
  | uplink.nu01.com | `/` | (2xx only) |
  | uplink.nu01.com | `/health` | `"status": "ok"` |

- **Cost:** about $0. 8,640 short runs a month, the schedule and one alarm
  are within the free tiers; email notifications are free.
- **Tags:** `project=nu01`, `tenancy=shared`. CI doesn't deploy it: the
  GitHub deploy roles may touch only the site stacks.
