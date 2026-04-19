---
name: plane
description: >
  Plane.so REST CLI as a Claude Code skill. Use whenever the agent needs to
  read or write Plane resources (projects, issues, cycles, comments, time-entries,
  labels, states) without loading the Plane MCP server's tool schemas. Runtime
  help via `plane help <resource>`. Placeholder skill definition — full SKILL.md
  lands in Unit 8.
---

# plane

Thin shell wrapper around the Plane.so REST API. Installed via `./install.sh` from
the source repo. Zero end-user runtime deps beyond POSIX shell, `curl`, `jq ≥ 1.6`,
and `bash ≥ 4`.

**Unit 1 placeholder.** This file is replaced in Unit 8 with the agent-facing
reference: dispatcher help, exit codes, destructive verbs, quick examples. Until
then, see:

- `docs/plans/2026-04-19-001-feat-plane-skill-plan.md` — active plan.
- `docs/exit-codes.md` — exit-code contract.
- `docs/contract-claude-plane.md` — shared config contract.

## Install

```
./install.sh           # copy mode (default)
./install.sh --symlink # symlink mode (for maintainers)
./uninstall.sh
```

Before first run: `cp docs/example-plane-config ~/.claude/.plane && chmod 600 ~/.claude/.plane`, edit values, then set the API key in your shell env.
