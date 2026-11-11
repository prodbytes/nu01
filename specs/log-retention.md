# Log retention

The `nu01-log-retention` stack ([infra/log-retention.yaml](../infra/log-retention.yaml),
deployed by hand with [scripts/deploy-log-retention.sh](../scripts/deploy-log-retention.sh))
keeps CloudWatch logs in the account (us-east-1) for two weeks.

- **Job:** a Lambda function (`nu01-log-retention`, Python, arm64, 128 MB),
  run daily at 04:00 UTC by an EventBridge rule, sets a 14-day retention
  (`RetentionDays`) on every log group that has no retention or a longer
  one. CloudWatch then deletes log events older than that by itself.
- **Why daily:** Lambda makes a function's log group with no retention when
  the function first logs, and redeploying a stack whose template sets a
  longer retention puts it back; the next run caps it again.
- **Not deleted:** the log groups themselves. One whose events have all
  expired stays, empty and free.
- **Failing:** a run that can't change a log group raises and logs it; it
  isn't retried (the next run is a day later). Logs go to
  `/aws/lambda/nu01-log-retention` (14 days).
- **Tags:** `project=nu01`, `tenancy=shared`.
- **Cost:** about $0 (one short Lambda run a day).
