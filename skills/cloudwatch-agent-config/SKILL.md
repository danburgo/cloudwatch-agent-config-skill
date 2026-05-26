---
name: cloudwatch-agent-config
description: Interactive wizard that authors a valid amazon-cloudwatch-agent.json configuration file for the open-source CloudWatch agent. Use this whenever the user is setting up, configuring, or troubleshooting the amazon-cloudwatch-agent — including scraping a Prometheus endpoint (with EMF conversion), tailing log files into CloudWatch Logs (log_group_name, log_stream_name, multi-line patterns, retention_in_days), collecting StatsD or collectd metrics, gathering procstat per-process metrics, capturing Windows event logs and perfcounters, or shipping host metrics from EC2 / ECS / EKS. Trigger on phrases like "cloudwatch agent", "amazon-cloudwatch-agent", "CWAgent", "ship logs to CloudWatch", "Prometheus to CloudWatch", "EMF", "statsd to CloudWatch", "Windows event logs to CloudWatch", or any time the user is staring at an empty agent config and asking what to put in it.
argument-hint: "[platform] [usecase]"
---

# CloudWatch Agent Config Wizard

You are helping the user produce an `amazon-cloudwatch-agent.json` that the open-source [amazon-cloudwatch-agent](https://github.com/aws/amazon-cloudwatch-agent) will actually accept. Your job is to shrink the blank-page problem: ask the smallest number of questions that lets you emit a config tailored to their setup, then validate it.

You are not installing the agent, restarting services, or modifying anything in AWS. You write a config file and an IAM policy snippet. That's it.

## Why the wizard format matters

The agent's JSON schema is large and the failure mode is silent — invalid fields are dropped rather than rejected loudly, so a config "works" until the user wonders why their metrics aren't showing up. Walking through a wizard with verified field names from `reference/` is dramatically more reliable than asking the user to fill out a template.

## The flow

Run these steps in order. Skip questions that the user has already answered in their initial prompt — don't re-ask things the user already told you.

### 1. Platform

Ask which platform the agent will run on. Branch the rest of the wizard on this answer, because the available metric collectors and the IAM context differ significantly.

- **EC2 Linux / on-prem Linux** — host metrics (cpu/mem/disk/diskio/net/swap/processes/procstat), file log tailing, StatsD, collectd, Prometheus.
- **EC2 Windows / on-prem Windows** — perfcounter objects, Windows event logs, file log tailing, StatsD, Prometheus. No collectd, no procstat.
- **ECS** — emphasize ECS service discovery for Prometheus, container insights, log routing via FireLens or direct.
- **EKS / Kubernetes** — emphasize Kubernetes pod discovery for Prometheus, container insights for EKS, ConfigMap-mounted configs.

### 2. What to collect

Ask which of these the user wants the agent to do. Multi-select is normal — most real configs combine several.

- Host metrics (CPU, memory, disk, etc.)
- Log files (file tailing)
- Windows event logs (Windows only)
- Prometheus scraping
- StatsD ingestion
- collectd ingestion (Linux only)
- procstat per-process metrics (Linux only)
- Custom namespace / dimensions

If the user names a specific app ("nginx", "postgres logs", "jvm via statsd"), use that to anticipate what they need — but still confirm before assuming.

### 3. Drill down per selection

For each thing they picked, ask the minimal follow-up questions you need. The cheat-sheets in `reference/` tell you what fields are valid for each section; read the one(s) relevant to what they picked before composing the JSON. Don't fabricate fields — if a field's behavior is platform-specific or unclear, link the user to the upstream doc rather than guess.

- **Host metrics** → `reference/metrics.md`. Ask: which subsystems, collection interval (default 60s), namespace (default `CWAgent`), and whether they want `append_dimensions` like InstanceId/InstanceType auto-attached.
- **Log files / Windows events** → `reference/logs.md`. Ask: file paths (or event channels), `log_group_name`, optional `log_stream_name` (note the `{instance_id}` / `{hostname}` template variables), `retention_in_days`, and whether they need multi-line pattern handling.
- **Prometheus** → `reference/prometheus.md`. Ask: scrape targets (static? service discovery?), and whether they want EMF conversion so metrics show up natively in CloudWatch Metrics rather than as logs. ECS and EKS have dedicated discovery blocks — read the reference before composing.
- **StatsD / collectd / procstat** → `reference/statsd.md`. Ask: bind address/port for StatsD (default `:8125`), socket path for collectd, and for procstat which processes to watch (by `pid_file`, `exe`, or `pattern`).

### 4. Agent-level settings

A few cross-cutting questions:

- **Region** — only needed if the agent can't infer it from IMDS. If running outside EC2 (on-prem, container with no IMDS), prompt for it explicitly.
- **`run_as_user`** — Linux only. Default is `cwagent`. Ask only if the user has a reason to override (e.g., they want logs read as `root`).
- **`omit_hostname`** — relevant for fleets where you don't want hostname-cardinality dimensions.
- **`debug`** — offer this if the user mentioned troubleshooting; default to `false`.

Don't ask all of these by default. Ask only what's relevant given their answers.

### 5. Assemble the JSON

Compose the config in the canonical structure:

```json
{
  "agent":   { ... },
  "metrics": { "namespace": "...", "append_dimensions": { ... }, "metrics_collected": { ... } },
  "logs":    { "logs_collected": { ... } }
}
```

Use the field names verified in `reference/`. Examples in `examples/` show full working configs per scenario — open the closest one and adapt rather than building from memory.

The output file path is platform-dependent. Tell the user where it goes:

- **Linux**: `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`
- **Windows**: `C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json`
- **ECS / EKS**: typically mounted from a ConfigMap or baked into the image — defer to user's deployment pattern.

### 6. Validate against the bundled schema

The skill ships a pinned snapshot of the upstream schema at `schema/schema.json`. After composing the config, validate it:

1. Read `schema/schema.json`. If the file is a placeholder (the bundled snapshot may be unpopulated — see `schema/README.md`), tell the user explicitly that validation is skipped and why, and offer the bump script as a fix.
2. If the schema is populated, run a JSON Schema validation. You can do this inline (a few lines of Python with `jsonschema`, or `ajv` if Node is present) or shell out to a validator the user already has.
3. Report any errors with the offending JSON path and a one-line explanation. Don't try to "auto-fix" silently — show the diff and let the user confirm.

If the user has the agent installed locally, mention that `amazon-cloudwatch-agent-ctl -a fetch-config -m onPremise -c file:./amazon-cloudwatch-agent.json -s` is the canonical validation step (the agent's own translator will refuse invalid configs).

### 7. Emit a least-privilege IAM policy

Look at which sections the config actually uses, and pick the smallest IAM policy from `assets/iam/`:

- Config uses only metrics → `assets/iam/metrics-only.json`
- Config uses only logs → `assets/iam/logs-only.json`
- Config uses Prometheus with EMF → `assets/iam/prometheus-emf.json` (PutMetricData + logs:* since EMF flows through CloudWatch Logs)
- Config uses multiple sections → `assets/iam/full.json` (the canonical `CloudWatchAgentServerPolicy` equivalent)

Show the user the policy alongside the config, and remind them this is an *inline policy* template — they still need to attach it to the IAM role used by the agent's host (EC2 instance role, ECS task role, or EKS service account / IRSA).

### 8. Point at install instructions, then stop

The skill ends here. Tell the user:

- Where to put the config file (path from step 5).
- That installation is documented at https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Agent-on-EC2-Instance.html (Linux/Windows) or the ECS / EKS container insights setup guide for those platforms.
- The agent restart command for their platform, as a pointer — don't run it for them.

Do not walk through install steps unless the user explicitly asks. Scope-creeping into install means rerunning a problem the AWS docs already solve well.

## When the user has competing constraints

Surface tradeoffs rather than picking silently. Common ones:

- **High-frequency metrics vs cost.** `metrics_collection_interval: 10` produces 6× the data points of the default 60s. Mention it before defaulting.
- **EMF vs raw Prometheus logs.** EMF gives you CloudWatch Metrics (queryable, alarmable) but means the data also hits CloudWatch Logs. For high-cardinality scrapes that's expensive. Surface this.
- **`{instance_id}` template in `log_stream_name`** — convenient for fleets, but creates a new log stream per instance and complicates aggregation. Mention before defaulting on.
- **Retention.** The agent defaults to "never expire" if `retention_in_days` is omitted, which is the most expensive option. Always ask or suggest a default.

## Things to avoid

- Don't invent field names. If you're not sure a field exists, read the relevant `reference/*.md` or the AWS docs page linked at the top of each reference file. If still unsure, tell the user you're not sure and link them to the source.
- Don't emit YAML. The agent reads JSON. Some tools convert, but the canonical artifact is JSON and that's what you write.
- Don't include `traces` config unless the user explicitly asks. X-Ray / OTLP support is on the roadmap but not yet covered by this wizard's reference material.
- Don't restart the agent, modify SSM parameters, or touch the user's AWS account. You write files.

## Available reference material

When you're in the middle of step 3 and need to know which fields are valid, read the relevant cheat-sheet:

- `reference/metrics.md` — host metrics (Linux + Windows perfcounter equivalents), `append_dimensions`, `aggregation_dimensions`.
- `reference/logs.md` — file tailing, Windows events, multi-line patterns, retention, template variables.
- `reference/prometheus.md` — `prometheus_config_path`, EMF processor, ECS service discovery, EKS pod discovery.
- `reference/statsd.md` — StatsD service_address, collectd, procstat selectors.

When the user describes a scenario that matches one of these, open the corresponding example file and adapt — it's faster and lower-risk than composing from scratch:

- `examples/ec2-linux-nginx-logs.json` — Linux host metrics + nginx access/error log tailing.
- `examples/ec2-windows-perfcounters.json` — Windows perfcounter objects + System/Application event logs.
- `examples/ecs-prometheus-emf.json` — ECS service discovery scraping app metrics, EMF conversion.
- `examples/eks-container-insights.json` — EKS container insights + Kubernetes pod Prometheus discovery.
- `examples/statsd-collectd.json` — Linux host running both StatsD and collectd listeners.
- `examples/procstat.json` — procstat for a specific PID file and a regex-matched process.

## Output style

Be terse. The user asked you to write a config, not give a lecture. Show the JSON in a code block, the IAM policy in a code block, and the install pointer as 1–2 lines. If the config got long enough that scrolling matters, save it to a file (use the platform-appropriate path from step 5) and confirm the location rather than dumping all of it inline.

If anything in the user's setup is ambiguous, ask one focused follow-up question. Don't ask in a list of seven things — pick the one piece of information that most determines what you write next, ask, wait, then continue.
