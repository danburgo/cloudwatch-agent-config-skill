# Reference: `metrics_collected.prometheus`

Canonical sources:
- Setup overview: <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights-Prometheus-Setup.html>
- ECS service discovery: <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights-Prometheus-Setup-autodiscovery-ecs.html>
- EKS service discovery: <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights-Prometheus-Setup-configure.html>
- Upstream samples: <https://github.com/aws/amazon-cloudwatch-agent/tree/main/translator/config/sampleSchema>

The Prometheus collector scrapes any Prometheus-format `/metrics` endpoint and ships the result to CloudWatch — optionally converting to **EMF** (Embedded Metric Format) so the data lands as queryable CloudWatch Metrics rather than just as log lines.

This is one of the more complex sections of the agent config. The structure splits across two places: a standard **Prometheus YAML** file (the same syntax you'd use with native Prometheus) and the agent's **JSON block** that points at it plus adds EMF / service-discovery glue.

## Shape

```json
{
  "metrics": {
    "metrics_collected": {
      "prometheus": {
        "prometheus_config_path": "/etc/cwagent-prom/prom-config.yaml",
        "emf_processor": { ... },
        "ecs_service_discovery": { ... }
      }
    }
  }
}
```

| Field | Type | Notes |
|---|---|---|
| `prometheus_config_path` | string | Required. Path to a Prometheus-format YAML scrape config on disk (or `env:VARNAME` to read from an environment variable). |
| `emf_processor` | object | Optional but usually wanted. Configures which scraped metrics become CloudWatch metrics, and under what namespace/dimensions. |
| `ecs_service_discovery` | object | ECS only. Discovers task targets via ECS APIs / Docker labels. Mutually exclusive with embedding ECS SD in the YAML. |
| `cluster_name` | string | EKS only. Used as a dimension for container insights. |

## The Prometheus YAML side

This is a standard Prometheus `scrape_configs` document. Minimal example:

```yaml
global:
  scrape_interval: 1m
  scrape_timeout: 10s
scrape_configs:
  - job_name: 'myapp'
    static_configs:
      - targets: ['localhost:9100', 'localhost:9090']
```

The agent uses the same relabeling, sd_configs, and tls_config support as upstream Prometheus 2.x. If the user already has a Prometheus YAML, they can usually reuse it as-is. Reference: <https://prometheus.io/docs/prometheus/latest/configuration/configuration/>.

## `emf_processor`

EMF conversion is what turns scraped Prometheus metrics into CloudWatch Metrics. Without it, scrapes still land in CloudWatch Logs (as raw text in a log group) but they don't show up in the CloudWatch Metrics console.

```json
{
  "emf_processor": {
    "metric_declaration_dedup": true,
    "metric_namespace": "ECS/ContainerInsights/Prometheus",
    "metric_unit": {
      "jvm_memory_bytes_used": "Bytes",
      "http_requests_total": "Count"
    },
    "metric_declaration": [
      {
        "source_labels": ["job"],
        "label_matcher": "^myapp$",
        "dimensions": [["ClusterName", "TaskDefinitionFamily"]],
        "metric_selectors": [
          "^jvm_memory_bytes_used$",
          "^http_requests_total$"
        ]
      }
    ]
  }
}
```

| Field | Notes |
|---|---|
| `metric_namespace` | CloudWatch Metrics namespace where converted metrics land. |
| `metric_declaration[]` | Each entry is a filter + dimension set. Only metrics matching `metric_selectors` from sources whose labels match `source_labels` + `label_matcher` get converted. |
| `metric_declaration[].dimensions` | Array of arrays. Each inner array is one dimension combination (you can declare multiple for multi-axis rollups). |
| `metric_unit` | Map of metric name → CloudWatch unit (`Bytes`, `Count`, `Percent`, `Seconds`, `Milliseconds`, etc.). |
| `metric_declaration_dedup` | Deduplicates declarations with the same dimension set. |

If a scraped metric isn't matched by any `metric_declaration`, it still lands in CloudWatch Logs but doesn't become a CloudWatch Metric — useful for keeping a paper trail of everything while only paying CloudWatch Metrics cost on the ones you actually alarm on.

## `ecs_service_discovery` (ECS only)

Lets the agent find scrape targets dynamically as ECS tasks come and go. Three discovery flavors, often combined:

```json
{
  "ecs_service_discovery": {
    "sd_frequency": "1m",
    "sd_result_file": "/tmp/cwagent_ecs_auto_sd.yaml",
    "docker_label": {
      "sd_port_label": "ECS_PROMETHEUS_EXPORTER_PORT",
      "sd_metrics_path_label": "ECS_PROMETHEUS_METRICS_PATH",
      "sd_job_name_label": "ECS_PROMETHEUS_JOB_NAME"
    },
    "task_definition_list": [
      {
        "sd_job_name": "nginx-prom",
        "sd_metrics_ports": "9113",
        "sd_metrics_path": "/metrics",
        "sd_task_definition_arn_pattern": ".*:task-definition/.*nginx.*:[0-9]+"
      }
    ],
    "service_name_list_for_tasks": [
      {
        "sd_job_name": "my-service",
        "sd_metrics_ports": "8080",
        "sd_metrics_path": "/actuator/prometheus",
        "sd_service_name_pattern": "^my-service$"
      }
    ]
  }
}
```

The `sd_result_file` is where the agent writes the auto-discovered targets in Prometheus-YAML format; the user's `prometheus_config_path` YAML should `file_sd_configs` reference that path:

```yaml
scrape_configs:
  - job_name: 'cwagent-ecs-file-sd-config'
    file_sd_configs:
      - files: ["/tmp/cwagent_ecs_auto_sd.yaml"]
```

## EKS / Kubernetes

EKS uses standard Prometheus `kubernetes_sd_configs` inside the YAML — no special agent-side block. The agent itself runs as a DaemonSet (typically via the CloudWatch Container Insights setup) and uses an IRSA-bound service account for permissions.

For container insights specifically, the upstream `prometheus-eks.yaml` ConfigMap manifest from AWS is the canonical starting point: <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights-Prometheus-Setup-configure.html>.

## When to bail to the docs

If the user is asking about anything beyond the basics in this file — custom relabeling, mTLS to scrape targets, federated Prometheus, Managed Prometheus (AMP) as destination, exemplars — link them to the AWS docs and the upstream Prometheus reference rather than guessing. The Prometheus config surface is large and field names there are upstream Prometheus's responsibility, not the agent's.
