# Reference: `logs` section

Canonical source: <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html>
Upstream schema: <https://github.com/aws/amazon-cloudwatch-agent/blob/main/translator/config/schema.json>

The `logs` block ships log content into CloudWatch Logs. Two collectors: `files` (everywhere) and `windows_events` (Windows only).

## Top-level fields

| Field | Type | Notes |
|---|---|---|
| `logs_collected` | object | **Required.** Holds the `files` and/or `windows_events` sub-blocks. |
| `log_stream_name` | string | Default stream name used when an individual entry doesn't specify one. Supports template variables (see below). |
| `force_flush_interval` | integer | Seconds. Default 5. |
| `endpoint_override` | string | Custom CloudWatch Logs endpoint. |
| `credentials.role_arn` | string | Cross-account writes. |

### Template variables (any string field)

| Variable | Resolves to |
|---|---|
| `{instance_id}` | EC2 instance ID (from IMDS) |
| `{hostname}` | Reported hostname |
| `{local_hostname}` | Local hostname from `/etc/hostname` or equivalent |
| `{ip_address}` | First non-loopback IPv4 address |
| `{date}` | YYYY-MM-DD |

Useful for `log_stream_name` to fan out per host without naming each one. Watch the tradeoff: per-instance streams complicate aggregation queries — see the wizard's "competing constraints" section.

## `logs_collected.files.collect_list[]`

Each entry tails one file or glob. Fields:

| Field | Required | Notes |
|---|---|---|
| `file_path` | yes | Absolute path. Supports `*` and `?` glob wildcards. E.g. `/var/log/nginx/access.log` or `/var/log/app/*.log`. |
| `log_group_name` | no | CloudWatch log group — **strongly recommended**; if omitted the agent derives the name from the file path. Created if absent (if the IAM policy allows `logs:CreateLogGroup`). |
| `log_stream_name` | no | Defaults to the top-level `log_stream_name`. Supports template variables. |
| `retention_in_days` | no | Sets retention on the log group. Valid: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 2192, 2557, 2922, 3288, 3653. Omit and the group keeps logs forever (expensive default). |
| `timezone` | no | `UTC` or `Local`. Default `Local`. |
| `timestamp_format` | no | strftime-style format describing the timestamp in your log lines. E.g. `%Y-%m-%d %H:%M:%S`. Used in tandem with `multi_line_start_pattern`. |
| `multi_line_start_pattern` | no | Regex matching the first line of a multi-line entry. Common shortcut: set it to `{timestamp_format}` to reuse the timestamp regex. Without this, every line is one event. |
| `encoding` | no | Default `utf-8`. Supports `ascii`, `utf-16`, `windows-1252`, `euc-jp`, etc. — see upstream docs for the full list. |
| `filters` | no | Array of `{type: "include" \| "exclude", expression: "<regex>"}` applied in order. Useful for dropping noisy debug lines. |
| `blacklist` | no | Single regex; drop matching lines. (Older field; `filters` is preferred.) |
| `publish_multi_logs` | no | Boolean. If true, treats each match in the glob as a separate stream. |
| `trim_timestamp` | no | Boolean. Default false. Removes the matched timestamp from the event body. |
| `backpressure_mode` | no | Controls backpressure handling. See upstream docs — leave unset unless you've hit issues. |

### Minimal file-tail example

```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/myapp/nginx/access",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 14,
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/myapp/application",
            "log_stream_name": "{hostname}-{date}",
            "retention_in_days": 30,
            "timestamp_format": "%Y-%m-%d %H:%M:%S",
            "multi_line_start_pattern": "{timestamp_format}",
            "filters": [
              {"type": "exclude", "expression": "DEBUG"}
            ]
          }
        ]
      }
    }
  }
}
```

## `logs_collected.windows_events.collect_list[]` (Windows only)

Each entry subscribes to a Windows event channel. Fields:

| Field | Required | Notes |
|---|---|---|
| `event_name` | yes | Channel name. Common: `System`, `Application`, `Security`, `Setup`, or any custom channel name from Event Viewer. The agent rejects `Forwarded Events` — subscribe to the source channels instead. |
| `event_levels` | one of¹ | Array of severities to include. Valid: `"INFORMATION"`, `"WARNING"`, `"ERROR"`, `"CRITICAL"`, `"VERBOSE"`. |
| `event_ids` | one of¹ | Array of specific numeric event IDs to include. Omit to take all matching the levels. |
| `filters` | one of¹ | Array of `{type, expression}` — same shape as file filters. |
| `log_group_name` | no | CloudWatch log group — **strongly recommended**; if omitted the agent derives a default. |
| `log_stream_name` | no | Defaults to the top-level value. |
| `event_format` | no | `"xml"` (default) or `"text"`. XML preserves structured fields; text is human-friendlier. |
| `retention_in_days` | no | Same valid values as files. |

¹ The schema requires at least one of `event_levels`, `event_ids`, or `filters`. Specifying `event_levels` is the usual case.

### Minimal Windows-events example

```json
{
  "logs": {
    "logs_collected": {
      "windows_events": {
        "collect_list": [
          {
            "event_name": "System",
            "event_levels": ["ERROR", "CRITICAL"],
            "log_group_name": "/windows/system",
            "log_stream_name": "{instance_id}",
            "event_format": "xml",
            "retention_in_days": 30
          },
          {
            "event_name": "Application",
            "event_levels": ["WARNING", "ERROR", "CRITICAL"],
            "event_ids": [1000, 1001, 1002],
            "log_group_name": "/windows/application",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 14
          }
        ]
      }
    }
  }
}
```

## Things that bite people

- **No `retention_in_days` = forever.** This is by far the most common cost surprise. Always ask the user.
- **`log_stream_name: {instance_id}` per host** creates one stream per instance. Convenient for fleets, painful for log aggregation queries that span instances. Mention before defaulting on.
- **Multi-line without `multi_line_start_pattern`** turns one stack trace into 30 events. If the user is shipping anything with stack traces, prompt for a pattern.
- **Globs match at agent start**, not continuously. A new file added later that matches the glob *will* be picked up (the agent watches the directory), but the user should sanity-check this if they rely on it.
- **`log_group_name` must satisfy the IAM policy.** If the policy is scoped to `/myapp/*`, the user can't write to `/other/group`. Surface this when emitting the IAM snippet.
