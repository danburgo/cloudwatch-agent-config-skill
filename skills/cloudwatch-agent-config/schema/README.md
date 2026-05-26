# Pinned schema snapshot

This directory holds a version-pinned snapshot of the open-source CloudWatch agent's JSON schema. The wizard validates generated configs against it before handing the file to the user.

## Why pin it?

Two reasons:

1. **Determinism.** A given version of the skill should always validate the same way. Pulling the schema live at every invocation means an unrelated upstream change can suddenly make every prior config "invalid" without you having edited a thing.
2. **Offline operation.** Skills run in sandboxed Claude Code sessions that may not have network access to GitHub. A bundled snapshot makes the wizard work everywhere.

## Current snapshot

`schema.json` — **placeholder. Not yet populated.** Run `scripts/bump-schema.sh` from the skill root to populate it, then commit the result.

`SCHEMA_VERSION` — written by the bump script. Records the upstream commit SHA that the snapshot was taken from.

## Bumping

```
./scripts/bump-schema.sh
```

The script:

1. Fetches the latest `translator/config/schema.json` from `aws/amazon-cloudwatch-agent` on `main`.
2. Writes it to `skills/cloudwatch-agent-config/schema/schema.json`.
3. Records the commit SHA in `skills/cloudwatch-agent-config/schema/SCHEMA_VERSION`.
4. Prints the diff so you can review what changed.

Always review the diff before committing. Upstream restructures break the validator silently if you bump without checking — the agent itself moved field locations between major versions in the past.

## If the snapshot is missing

If `schema.json` is the placeholder (or absent), the wizard's validation step is a no-op and it tells the user explicitly that validation was skipped. The wizard continues to produce a config based on the field names documented in `reference/`, so the skill still works — you just don't get the schema-validation safety net.
