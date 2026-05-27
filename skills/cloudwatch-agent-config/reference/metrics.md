# Reference: `metrics` section

Canonical source: <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html>
Upstream schema: <https://github.com/aws/amazon-cloudwatch-agent/blob/main/translator/config/schema.json>

The `metrics` block ships host metrics (and StatsD / collectd / Prometheus output — see their respective cheat-sheets) to CloudWatch Metrics under a namespace you choose.

## Top-level fields

| Field | Type | Notes |
|---|---|---|
| `namespace` | string | Default `CWAgent`. Max 255 chars. Shows up as the metric namespace in CloudWatch. |
| `append_dimensions` | object | Auto-attaches dimensions to every metric. Keys you can use: `ImageId`, `InstanceId`, `InstanceType`, `AutoScalingGroupName` with `${aws:ImageId}` / `${aws:InstanceId}` / `${aws:InstanceType}` / `${aws:AutoScalingGroupName}` placeholder values. |
| `aggregation_dimensions` | array of arrays | Each inner array is one rollup dimension set. E.g. `[["InstanceId"], ["AutoScalingGroupName"], []]` produces three aggregations. |
| `metrics_collected` | object | **Required.** Holds the per-subsystem config — see below. |
| `endpoint_override` | string | Custom CloudWatch endpoint (VPC endpoint, FIPS, etc.). |
| `force_flush_interval` | integer | Seconds. Default 60. |
| `metrics_destinations` | object | Optional. `cloudwatch: {}` (default) or `amp: { workspace_id: "..." }` for Managed Prometheus. |
| `credentials.role_arn` | string | For cross-account writes. |

## Linux `metrics_collected` subsystems

All Linux subsystems take the same shape: a `measurement` array of fields, an optional `resources` array (e.g. mount points, devices, interfaces), and an optional per-subsystem `metrics_collection_interval` that overrides the agent-level default.

### `cpu`
- `measurement`: any of `usage_idle`, `usage_iowait`, `usage_irq`, `usage_nice`, `usage_softirq`, `usage_steal`, `usage_system`, `usage_user`, `usage_active`, `usage_guest`, `usage_guest_nice`, `time_*` variants.
- `resources`: `["*"]` for per-CPU; omit for aggregate only.
- `totalcpu`: boolean, include totals across all CPUs.

### `mem`
- `measurement`: `active`, `available`, `available_percent`, `buffered`, `cached`, `free`, `inactive`, `shared`, `slab`, `sreclaimable`, `sunreclaim`, `total`, `used`, `used_percent`.

### `disk`
- `measurement`: `free`, `inodes_free`, `inodes_total`, `inodes_used`, `total`, `used`, `used_percent`.
- `resources`: mount paths, e.g. `["/", "/var"]`. Use `["*"]` for all.
- `ignore_file_system_types`: e.g. `["tmpfs", "devtmpfs"]`.
- `drop_device`: boolean. Drops the `device` dimension to reduce cardinality.

### `diskio`
- `measurement`: `iops_in_progress`, `io_time`, `reads`, `read_bytes`, `read_time`, `writes`, `write_bytes`, `write_time`.
- `resources`: device names, e.g. `["nvme0n1", "xvda"]`.

### `net`
- `measurement`: `bytes_recv`, `bytes_sent`, `drop_in`, `drop_out`, `err_in`, `err_out`, `packets_recv`, `packets_sent`.
- `resources`: interface names, e.g. `["eth0"]`.

### `netstat`
- `measurement`: `tcp_close`, `tcp_close_wait`, `tcp_closing`, `tcp_established`, `tcp_fin_wait1`, `tcp_fin_wait2`, `tcp_last_ack`, `tcp_listen`, `tcp_none`, `tcp_syn_sent`, `tcp_syn_recv`, `tcp_time_wait`, `udp_socket`.

### `swap`
- `measurement`: `free`, `used`, `used_percent`.

### `processes`
- `measurement`: `blocked`, `dead`, `idle`, `paging`, `running`, `sleeping`, `stopped`, `total`, `total_threads`, `wait`, `zombies`.

### `procstat`
See `reference/statsd.md` for procstat selectors.

### `statsd`, `collectd`, `prometheus`
See their dedicated cheat-sheets.

## Windows performance counters

On Windows, each Performance Monitor object is a key directly under `metrics_collected` — there is no `perfcounter` wrapper. Each object takes the same shape as a Linux subsystem: a `measurement` array plus an optional `resources` array. Standard objects:

| Object name | Common measurements | Typical resources |
|---|---|---|
| `Processor` | `% Idle Time`, `% Interrupt Time`, `% Processor Time`, `% User Time` | `["*"]` for per-core, `["_Total"]` for aggregate |
| `Memory` | `Available Bytes`, `Available MBytes`, `% Committed Bytes In Use`, `Cache Faults/sec` | not used |
| `LogicalDisk` | `% Free Space`, `Free Megabytes`, `Disk Read Bytes/sec`, `Disk Write Bytes/sec` | `["*"]` or specific drives like `["C:"]` |
| `PhysicalDisk` | `% Disk Time`, `Disk Bytes/sec`, `Disk Reads/sec`, `Disk Writes/sec` | `["*"]` or `["0 C:"]` |
| `Network Interface` | `Bytes Received/sec`, `Bytes Sent/sec`, `Packets Received/sec`, `Packets Sent/sec` | adapter names |
| `Paging File` | `% Usage`, `% Usage Peak` | `["\\??\\C:\\pagefile.sys"]` |
| `System` | `Processor Queue Length`, `System Calls/sec`, `Context Switches/sec` | not used |
| `TCPv4` / `TCPv6` | `Connections Established`, `Segments/sec` | not used |

Each object uses this shape — the object name is the key, and `measurement` entries are plain counter-name strings or `{name, rename, unit}` objects:
```json
{
  "metrics_collected": {
    "LogicalDisk": {
      "measurement": [
        {"name": "% Free Space", "rename": "DiskFreePercent", "unit": "Percent"},
        "Free Megabytes"
      ],
      "resources": ["*"],
      "metrics_collection_interval": 60
    }
  }
}
```

Counter names are case-sensitive and must match the exact Windows Performance Monitor label. When in doubt, check the Performance Monitor UI (`perfmon.exe`) or the upstream sample at <https://github.com/aws/amazon-cloudwatch-agent/blob/main/translator/config/sampleSchema>.

## Drop / rename per-metric

Each subsystem entry may include a `drop_original_metrics` array (subsystem-specific metric names) to suppress shipping the original after a rename, and `append_dimensions` to attach extra dimensions just to that subsystem's metrics.

## Minimal valid example

```json
{
  "metrics": {
    "namespace": "MyApp",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": ["usage_active", "usage_iowait"],
        "totalcpu": true,
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["*"],
        "ignore_file_system_types": ["tmpfs", "devtmpfs"]
      }
    }
  }
}
```
