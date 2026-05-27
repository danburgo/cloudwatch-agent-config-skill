# cloudwatch-agent-config-skill

A Claude Code skill that walks you through authoring an `amazon-cloudwatch-agent.json` configuration file. It exists to kill "blank page syndrome" — the moment where you know the CloudWatch agent supports what you need (host metrics, log tailing, Prometheus scraping, StatsD, procstat, Windows events, ECS/EKS service discovery), but staring at an empty JSON file is enough friction that you put it off another sprint.

Invoke it, answer a handful of questions, and you get a config that the agent will actually accept — plus a least-privilege IAM policy snippet scoped to whatever you turned on.

## What the skill does

- **Asks** for your platform (EC2 Linux, EC2 Windows, ECS, EKS) and which data you want to collect.
- **Generates** a valid `amazon-cloudwatch-agent.json` using field names verified against the upstream [aws/amazon-cloudwatch-agent](https://github.com/aws/amazon-cloudwatch-agent) schema.
- **Validates** the generated config against a bundled, version-pinned snapshot of the agent's JSON schema.
- **Emits** an IAM policy starter scoped to the actions your config uses. (The multi-section `full.json` variant is the exception: it mirrors AWS's managed `CloudWatchAgentServerPolicy` and is intentionally a broader superset.)
- **Points you** at the canonical install commands for your platform. (Install itself is out of scope; this skill is purely about config.)

It does *not* install the agent, modify SSM parameters, restart services, or touch your AWS account. It writes a file.

## Install

### From the Claude community plugin marketplace

```
/plugin marketplace add danburgo/cloudwatch-agent-config-skill
/plugin install cloudwatch-agent-config
```

Then invoke via `/cloudwatch-agent-config` or just ask Claude to "help me write a cloudwatch agent config" and it should trigger automatically.

### Local development install

```
git clone https://github.com/danburgo/cloudwatch-agent-config-skill.git
cd cloudwatch-agent-config-skill
claude --plugin-dir .
```

## Repository layout

```
.
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── cloudwatch-agent-config/
│       ├── SKILL.md               # The wizard itself
│       ├── reference/             # Cheat-sheets per section (metrics, logs, prometheus, statsd)
│       ├── examples/              # Curated, working configs per scenario
│       ├── schema/                # Pinned upstream JSON schema (see schema/README.md)
│       ├── assets/iam/            # IAM policy variants (scoped per use case; full.json = CloudWatchAgentServerPolicy superset)
│       └── scripts/bump-schema.sh # Refresh the pinned schema from upstream
├── evals/
│   └── evals.json                 # Test prompts used to iterate on the skill
├── LICENSE
└── README.md
```

## How the skill stays accurate

CloudWatch agent config is notoriously easy to fabricate fields for — names look plausible until the agent silently drops them. To avoid that:

1. **Field names are sourced from the upstream schema**, not from training data. The skill's reference files cite the AWS docs page and the upstream schema file for every section.
2. **Examples are minimal and verified.** Each file under `examples/` is hand-checked against the upstream sample configs.
3. **Uncertainty is surfaced, not guessed.** Where a field's behavior is platform-dependent or version-dependent, the skill instructs Claude to link the user to the upstream doc section rather than invent a value.

## Contributing examples

If you have a `amazon-cloudwatch-agent.json` you'd like to contribute as a reference scenario:

1. Strip any account-specific values (role ARNs, account IDs, internal hostnames).
2. Drop it into `skills/cloudwatch-agent-config/examples/` with a name like `<platform>-<usecase>.json`.
3. Add a one-paragraph header comment in a sibling `.md` file describing what it does and which agent version it was tested against.
4. Open a PR.

## Bumping the schema

The bundled schema snapshot lives at `skills/cloudwatch-agent-config/schema/schema.json`. To refresh it from the upstream repo:

```
./skills/cloudwatch-agent-config/scripts/bump-schema.sh
```

See `skills/cloudwatch-agent-config/schema/README.md` for what the script does and how to verify the result.

## Roadmap

- [x] Populate the pinned schema snapshot (see `schema/README.md`).
- [ ] Add traces / X-Ray / OTLP support to the wizard.
- [ ] Add CloudWatch Application Signals support.
- [ ] Optional `--dry-run` mode that emits the wizard's plan without writing files.
- [ ] Optional integration with the agent's local config-translator binary for canonical validation when present.
- [ ] Examples for cross-account configs (`credentials.role_arn`).

## License

Apache-2.0 — matching the upstream [amazon-cloudwatch-agent](https://github.com/aws/amazon-cloudwatch-agent) license. See [LICENSE](LICENSE).

## Acknowledgements

- Built on Anthropic's [Claude Code](https://www.anthropic.com/claude-code) skill system.
- Field names and validation rules are sourced from the AWS-maintained [amazon-cloudwatch-agent](https://github.com/aws/amazon-cloudwatch-agent) repository.
- Inspired by the same observation that drives every YAML-config generator: the most expensive part of any agent is the first config file.
