#!/usr/bin/env python3
"""Reports AWS cost per profile (account), per project, by month and by day.

    python3 scripts/cost-report.py [--profiles P ...] [--months N] [--days N] [--out DIR]

- Reads Cost Explorer through every AWS CLI profile (`aws configure
  list-profiles`, or --profiles). Profiles that reach the same account are
  reported once; profiles that can't (no credentials, an expired SSO login,
  an MFA prompt) are listed with the reason. Nothing ever waits for input.
- Per account: the current month to date and the N previous full months (3
  by default), and the last N days (14 by default), split by the `project`
  cost allocation tag (every nu01 stack has one; costs tagged with an old
  project name are folded into the new one, see ALIASES), then credits,
  refunds and tax, and the total; this month's forecast; and this month's
  usage per project by service.
- Writes a Markdown report and the same numbers as JSON to
  <out>/YYYY/MM/cost-report-YYYYMMDD-HHMMSSZ.{md,json} (UTC), out being
  reports/costs/ by default. git ignores reports/: the repository is public.
- Needs ce:GetCostAndUsage and ce:GetCostForecast. Each Cost Explorer
  request costs $0.01; a report makes four per account.
"""
import argparse
import datetime as dt
import json
import os
import re
import subprocess
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ALIASES = {"tabscan": "tabcam"}  # renamed projects: old tag value -> new
UNTAGGED = "(untagged)"
METRIC = "UnblendedCost"
TIMEOUT = 60  # seconds per AWS CLI call


class AwsError(Exception):
    pass


def aws(profile, *args):
    """Runs `aws <args>` as `profile` and returns its JSON output."""
    env = dict(os.environ, AWS_PROFILE=profile, AWS_PAGER="")
    try:
        proc = subprocess.run(["aws", *args, "--output", "json"], env=env, capture_output=True,
                              text=True, stdin=subprocess.DEVNULL, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        raise AwsError(f"no answer in {TIMEOUT}s")
    if proc.returncode != 0:
        lines = [l for l in proc.stderr.strip().splitlines() if l.strip()]
        message = lines[-1].replace("aws: [ERROR]: ", "") if lines else f"exit {proc.returncode}"
        code = re.search(r"An error occurred \((\w+)\)", message)  # e.g. NoCredentials
        raise AwsError(code.group(1) if code else message[:100])
    return json.loads(proc.stdout) if proc.stdout.strip() else {}


def ce_pages(profile, *args):
    """`aws ce <args>`, following NextPageToken."""
    pages, token = [], None
    while True:
        page = aws(profile, "ce", *args, *(["--next-page-token", token] if token else []))
        pages.append(page)
        token = page.get("NextPageToken")
        if not token:
            return pages


def project_of(key):
    """'project$grigri' -> 'grigri'; an empty tag value -> (untagged)."""
    value = key.split("$", 1)[1] if "$" in key else key
    return ALIASES.get(value, value) or UNTAGGED


def by_project_and_record_type(profile, start, end, granularity):
    """{period: {project: {record_type: amount}}}; periods 'YYYY-MM' or 'YYYY-MM-DD'."""
    out = defaultdict(lambda: defaultdict(lambda: defaultdict(float)))
    for page in ce_pages(profile, "get-cost-and-usage", "--time-period", f"Start={start},End={end}",
                         "--granularity", granularity, "--metrics", METRIC,
                         "--group-by", "Type=TAG,Key=project", "Type=DIMENSION,Key=RECORD_TYPE"):
        for period in page["ResultsByTime"]:
            key = period["TimePeriod"]["Start"][:7 if granularity == "MONTHLY" else 10]
            out[key]  # a period with no cost still gets its row
            for group in period["Groups"]:
                out[key][project_of(group["Keys"][0])][group["Keys"][1]] += \
                    float(group["Metrics"][METRIC]["Amount"])
    return out


def usage_by_project_and_service(profile, start, end):
    """{project: {service: amount}}, usage records only."""
    out = defaultdict(lambda: defaultdict(float))
    usage_only = json.dumps({"Dimensions": {"Key": "RECORD_TYPE", "Values": ["Usage"]}})
    for page in ce_pages(profile, "get-cost-and-usage", "--time-period", f"Start={start},End={end}",
                         "--granularity", "MONTHLY", "--metrics", METRIC, "--filter", usage_only,
                         "--group-by", "Type=TAG,Key=project", "Type=DIMENSION,Key=SERVICE"):
        for period in page["ResultsByTime"]:
            for group in period["Groups"]:
                out[project_of(group["Keys"][0])][group["Keys"][1]] += \
                    float(group["Metrics"][METRIC]["Amount"])
    return out


def forecast(profile, start, end):
    """The forecast total from start to end, or None (e.g. too little history)."""
    if start >= end:
        return None
    try:
        page = aws(profile, "ce", "get-cost-forecast", "--time-period", f"Start={start},End={end}",
                   "--granularity", "MONTHLY", "--metric", "UNBLENDED_COST")
    except AwsError:
        return None
    return float(page["Total"]["Amount"])


def money(amount):
    """'$1.23', '-$0.40', or '·' for less than half a cent either way."""
    if abs(amount) < 0.005:
        return "·"
    return f"-${-amount:,.2f}" if amount < 0 else f"${amount:,.2f}"


def table(header, rows, text_columns=1):
    """A Markdown table: the first text_columns left-aligned, the rest (money) right."""
    align = ["---"] * text_columns + ["---:"] * (len(header) - text_columns)
    lines = ["| " + " | ".join(header) + " |", "|" + "|".join(align) + "|"]
    return "\n".join(lines + ["| " + " | ".join(row) + " |" for row in rows])


def summarize(costs, periods):
    """Projects (untagged last), non-usage record types and net totals."""
    projects = sorted({p for k in periods for p in costs[k] if p != UNTAGGED})
    if any(UNTAGGED in costs[k] for k in periods):
        projects.append(UNTAGGED)
    others = sorted({rt for k in periods for p in costs[k].values() for rt in p} - {"Usage"})
    totals = {k: sum(sum(rt.values()) for rt in costs[k].values()) for k in periods}
    return projects, others, totals


def label(project, projects):
    if project != UNTAGGED:
        return f"**{project}**"
    return "_all (no project tags)_" if projects == [UNTAGGED] else f"_{UNTAGGED}_"


def usage(costs, period, project):
    return costs[period][project].get("Usage", 0.0)


def other(costs, period, record_type):
    return sum(rt.get(record_type, 0.0) for rt in costs[period].values())


def account_report(name, profiles, data, months, days, this_month):
    """The Markdown section for one account."""
    monthly, daily, services = data["monthly"], data["daily"], data["services"]
    md = [f"## {name}", "", f"Profiles: {', '.join(f'`{p}`' for p in profiles)}.", ""]

    projects, others, totals = summarize(monthly, months)
    header = ["Project"] + [f"{m} (to date)" if m == this_month else m for m in months]
    rows = [[label(p, projects)] + [money(usage(monthly, m, p)) for m in months] for p in projects]
    rows.append(["Usage"] + [money(sum(usage(monthly, m, p) for p in projects)) for m in months])
    rows += [[t] + [money(other(monthly, m, t)) for m in months] for t in others]
    rows.append(["**Total**"] + [f"**{money(totals[m])}**" for m in months])
    md += ["### By month", "", table(header, rows), ""]
    if data["forecast"] is not None:
        md += [f"Forecast for the rest of {this_month}: {money(data['forecast'])}.", ""]

    projects, others, totals = summarize(daily, days)
    header = ["Day"] + [label(p, projects) for p in projects] + others + ["**Total**"]
    rows = [[d] + [money(usage(daily, d, p)) for p in projects]
            + [money(other(daily, d, t)) for t in others] + [f"**{money(totals[d])}**"] for d in days]
    md += [f"### By day (last {len(days)} days)", "",
           "Usage per project, then credits, refunds and tax. The latest day may be incomplete.", "",
           table(header, rows), ""]

    md += [f"### {this_month} usage by service", ""]
    for project in sorted(services, key=lambda p: (p == UNTAGGED, p)):
        items = sorted(((s, a) for s, a in services[project].items() if abs(a) >= 0.005), key=lambda kv: -kv[1])
        if items:
            md += [f"#### {label(project, sorted(services))}", "",
                   table(["Service", "Cost"], [[s, money(a)] for s, a in items]), ""]
    return md


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--profiles", nargs="+", help="AWS CLI profiles (default: every configured one)")
    parser.add_argument("--months", type=int, default=3, help="previous full months to include (default 3)")
    parser.add_argument("--days", type=int, default=14, help="days in the daily table (default 14)")
    parser.add_argument("--out", default=str(ROOT / "reports" / "costs"), help="report folder (default reports/costs)")
    args = parser.parse_args()

    now = dt.datetime.now(dt.timezone.utc)
    today = now.date()
    end = today + dt.timedelta(days=1)  # Cost Explorer's End is exclusive
    starts = [today.replace(day=1)]
    for _ in range(args.months):
        starts.insert(0, (starts[0] - dt.timedelta(days=1)).replace(day=1))
    months = [s.strftime("%Y-%m") for s in starts]
    this_month = months[-1]
    first_day = today - dt.timedelta(days=args.days - 1)
    days = [str(first_day + dt.timedelta(days=i)) for i in range(args.days)]
    next_month = (today.replace(day=28) + dt.timedelta(days=4)).replace(day=1)

    profiles = args.profiles or subprocess.run(["aws", "configure", "list-profiles"], capture_output=True,
                                               text=True, stdin=subprocess.DEVNULL).stdout.split()
    accounts, skipped = {}, {}
    for profile in profiles:
        try:
            account = aws(profile, "sts", "get-caller-identity")["Account"]
        except AwsError as e:
            skipped[profile] = str(e)
            continue
        if account in accounts:
            accounts[account]["profiles"].append(profile)
            continue
        print(f"reading {account} as {profile}", flush=True)
        try:
            accounts[account] = {
                "profiles": [profile],
                "monthly": by_project_and_record_type(profile, starts[0], end, "MONTHLY"),
                "daily": by_project_and_record_type(profile, first_day, end, "DAILY"),
                "services": usage_by_project_and_service(profile, starts[-1], end),
                "forecast": forecast(profile, end, next_month),
            }
        except AwsError as e:
            skipped[profile] = f"account {account}: {e}"

    md = ["# AWS cost report", "",
          f"Generated {now:%Y-%m-%d %H:%M} UTC from Cost Explorer ({METRIC}, USD): months from "
          f"{starts[0]}, days from {first_day}, to {today}. Projects are the `project` cost allocation tag"
          + "".join(f"; `{old}` counts as `{new}`" for old, new in ALIASES.items()) + ".", ""]
    rows = []
    for account, data in accounts.items():
        totals = summarize(data["monthly"], months)[2]
        rows.append([f"`{account}`", ", ".join(data["profiles"])] + [money(totals[m]) for m in months]
                    + [money(data["forecast"]) if data["forecast"] is not None else "—"])
    md += ["## By profile", "", "Net totals (after credits) per account.", "",
           table(["Account", "Profiles"] + [f"{m} (to date)" if m == this_month else m for m in months]
                 + [f"Rest of {this_month} (forecast)"], rows, text_columns=2), ""]
    if skipped:
        md += ["Not readable:", ""] + [f"- `{p}`: {reason}" for p, reason in skipped.items()] + [""]
    for account, data in accounts.items():
        md += account_report(f"Account {account}", data["profiles"], data, months, days, this_month)

    stamp = now.strftime("%Y%m%d-%H%M%SZ")
    folder = Path(args.out) / now.strftime("%Y") / now.strftime("%m")
    folder.mkdir(parents=True, exist_ok=True)
    report = folder / f"cost-report-{stamp}.md"
    report.write_text("\n".join(md), encoding="utf-8")
    plain = lambda nested: json.loads(json.dumps(nested))  # defaultdicts -> dicts
    report.with_suffix(".json").write_text(json.dumps({
        "generated": now.isoformat(timespec="seconds"),
        "metric": METRIC,
        "currency": "USD",
        "months": months,
        "days": days,
        "aliases": ALIASES,
        "accounts": {a: {"profiles": d["profiles"], "monthly": plain(d["monthly"]), "daily": plain(d["daily"]),
                         "usage_by_service": {this_month: plain(d["services"])},
                         "forecast_rest_of_month": d["forecast"]} for a, d in accounts.items()},
        "not_readable": skipped,
    }, indent=2) + "\n", encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
