# Reference: `statsd`, `collectd`, `procstat`

Canonical sources:
- StatsD: <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-custom-metrics-statsd.html>
- collectd: <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-custom-metrics-collectd.html>
- procstat: <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-procstat-process-metrics.html>

All three live inside `metrics.metrics_collected`. They handle the "metrics from things that aren't the host itself" case.

## `statsd`

The agent embeds a StatsD listener. Anything in your stack that already speaks StatsD (e.g. via a `dogstatsd-client` library) can point at it and the metrics get forwarded to CloudWatch.

| Field | Default | Notes |
|---|---|---|
| `service_address` | `:8125` | UDP listen address. `:8125` listens on all interfaces; use `127.0.0.1:8125` to bind locally only. |
| `metrics_collection_interval` | 10 | Seconds. How often the agent flushes to CloudWatch. |
| `metrics_aggregation_interval` | 60 | Seconds. How often the agent aggregates StatsD events into a CloudWatch data point. Set to 0 to disable aggregation (every StatsD packet becomes a data point — usually undesirable). |
| `allowed_pending_messages` | 10000 | UDP receive queue length. Bump if you're dropping packets under load. |
| `drop_original_metrics` | — | Array of metric names to suppress after rename. |

### Minimal example

```json
{
  "metrics": {
    "metrics_collected": {
      "statsd": {
        "service_address": ":8125",
        "metrics_collection_interval": 10,
        "metrics_aggregation_interval": 60
      }
    }
  }
}
```

### StatsD metric type behavior

The agent honors standard StatsD types: counters (`c`), gauges (`g`), timers (`ms`), histograms (`h`), sets (`s`). Counters and timers get aggregated over `metrics_aggregation_interval`; gauges take the last value in the window.

### Cardinality warning

StatsD tag keys/values flow into CloudWatch as dimensions. CloudWatch charges per unique dimension combination, and dimensions are limited to 30 per metric. If the user is sending high-cardinality tags (user IDs, request paths), surface the cost implication and suggest pre-aggregating before the StatsD client emits.

## `collectd` (Linux only)

The agent embeds a collectd network-plugin listener that accepts the collectd binary protocol.

| Field | Default | Notes |
|---|---|---|
| `service_address` | `udp://127.0.0.1:25826` | URL-style. Supports `udp://`. |
| `name_prefix` | empty | Prefix prepended to every collectd metric name. |
| `collectd_security_level` | `none` | `none`, `sign`, or `encrypt`. Higher levels require `collectd_auth_file`. |
| `collectd_auth_file` | — | Path to a username/password file used by `sign` and `encrypt`. |
| `collectd_typesdb` | `["/usr/share/collectd/types.db"]` | Paths to collectd `types.db` files. |
| `metrics_aggregation_interval` | 60 | Same semantics as StatsD. |

### Minimal example

```json
{
  "metrics": {
    "metrics_collected": {
      "collectd": {
        "service_address": "udp://127.0.0.1:25826",
        "metrics_aggregation_interval": 60
      }
    }
  }
}
```

The user-side collectd config needs a matching `network` plugin pointing at the same address — see the collectd docs.

## `procstat`

Per-process metrics — CPU%, RSS, file descriptors, threads, etc. — for a specific process you identify by pid file, executable name, or regex.

### Selector

Each procstat entry selects exactly one of these:

| Field | Notes |
|---|---|
| `pid_file` | Path to a file containing the PID. Most reliable if the process you're watching writes one. |
| `exe` | Process name (the executable basename). Matches the first found. |
| `pattern` | Regex against the full `/proc/<pid>/cmdline`. Use when you need to disambiguate by command line args. |

You can have multiple procstat entries in an array — one per process you want to watch.

### Fields

| Field | Notes |
|---|---|
| `pid_file` / `exe` / `pattern` | **Exactly one required.** |
| `measurement` | Array of metric names. Common: `cpu_usage`, `cpu_time`, `cpu_time_system`, `cpu_time_user`, `memory_rss`, `memory_vms`, `memory_swap`, `memory_data`, `memory_locked`, `read_bytes`, `write_bytes`, `read_count`, `write_count`, `involuntary_context_switches`, `voluntary_context_switches`, `pid_count`, `num_threads`, `num_fds`. |
| `metrics_collection_interval` | Per-process override of the agent default. |
| `append_dimensions` | Attach extra dimensions to just this procstat entry's metrics. |

### Example: watch nginx by pid file, and a JVM by regex

```json
{
  "metrics": {
    "metrics_collected": {
      "procstat": [
        {
          "pid_file": "/var/run/nginx.pid",
          "measurement": ["cpu_usage", "memory_rss", "num_fds"],
          "metrics_collection_interval": 60
        },
        {
          "pattern": "java .*-jar .*myapp\\.jar",
          "measurement": ["cpu_usage", "memory_rss", "num_threads"],
          "metrics_collection_interval": 30
        }
      ]
    }
  }
}
```

### Things that bite people

- **`exe` matches the first found.** If two processes share an executable name, use `pattern` instead.
- **`pattern` is a regex, not a glob.** Escape dots, slashes, dollar signs.
- **The agent's IAM principal must be able to read `/proc/<pid>/...`.** On Linux this normally means `run_as_user: root` for procstat to be reliable across all processes — but only escalate if needed.
- **No procstat on Windows.** Use `perfcounter` with the `Process` object instead.
