# Manual Smoke Checklist

Pre-release verification against a live Plane instance. Run before tagging a release. Fills in under Unit 8.

**This file is a stub.** Unit 8 populates the real checklist against both Plane Cloud and the self-hosted instance at `plan.toledo.codes`.

## Intended shape

For each T1 resource, exercise:

- `list` (happy + pagination + `--all`)
- `get <id>`
- `create` (happy, with `--data @file` and with flag-driven body)
- `update`
- `delete` (dry-run first, then `--execute`)
- any resource-specific verb (cycle add/remove/transfer, time-entries bulk)

Plus meta:

- `plane doctor` against the target instance — all checks PASS.
- `plane version` — prints SHA, bash/curl/jq versions, captured-spec timestamp.
- `plane resolve PROJ-123` — returns a real work-item.
- `plane api GET /workspaces/<slug>/members/me/` — 2xx.
- Error injection: bad API key → exit 4. Bad slug → exit 9. HTTP URL → exit 3.

Each section should note: endpoint hit, request body summary, observed status, observed exit code, and pass/fail.
