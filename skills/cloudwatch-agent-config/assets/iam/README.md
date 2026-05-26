# IAM policy snippets

Each file is an inline IAM policy starter for one of the common CloudWatch agent use cases. They are *starters* — attach them to the IAM role that the agent's host uses (EC2 instance role, ECS task role, EKS IRSA service account role) and tighten further to your environment as needed.

| File | When to use |
|---|---|
| `full.json` | Equivalent to AWS-managed `CloudWatchAgentServerPolicy`. Use when the agent emits everything: metrics, logs, traces, EMF, SSM-stored config. |
| `metrics-only.json` | Config only ships CloudWatch Metrics. No log groups, no EMF, no traces. |
| `logs-only.json` | Config only ships CloudWatch Logs (file tailing, Windows events). No `metrics` block. |
| `prometheus-emf.json` | Prometheus scraping with EMF conversion. EMF flows through CloudWatch Logs, so this is `metrics-only.json` plus `logs:*` actions on the EMF log groups. |

## How to scope further

The `Resource: "*"` defaults are convenient but loose. Tighten by:

1. **Restricting log groups** to a prefix you own — change `"Resource": "*"` under `logs:*` to `"Resource": "arn:aws:logs:REGION:ACCOUNT:log-group:/myapp/*"`.
2. **Removing `logs:CreateLogGroup`** if you pre-create groups via IaC. The agent only needs `logs:CreateLogStream` + `logs:PutLogEvents` in that case.
3. **Removing `ssm:GetParameter`** if you don't store the agent config in SSM Parameter Store.

## Notes

- The agent reads region / instance metadata via IMDS — that doesn't need an IAM action.
- Cross-account writes need an `sts:AssumeRole` policy on the *caller* role and a trust policy on the *target* role; that's outside the scope of these snippets.
- For EKS use **IRSA** (IAM Roles for Service Accounts) rather than node-instance roles when possible — it gives you per-pod scoping and an audit trail.
