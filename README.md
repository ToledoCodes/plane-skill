# plane — Plane.so REST CLI as a Claude Code skill

A thin shell wrapper around the [Plane.so REST API](https://developers.plane.so/api-reference/introduction), packaged as an installable Claude Code skill. Agents read and write Plane resources without loading the Plane MCP server's tool schemas; discovery happens at runtime via `plane help <resource>`.

**Status: v1 in progress.** Units 1–6 are live: scaffolding, install/uninstall, core HTTP + config + preflight, OpenAPI capture + endpoint map, dispatcher with lazy help and `doctor`/`version`/`resolve` meta-commands, and the Tier-1 resource wrappers. The generic `plane api` escape hatch (Unit 7) and the final agent-facing `SKILL.md` (Unit 8) are not yet wired. See `docs/plans/2026-04-19-001-feat-plane-skill-plan.md`.

## Why

The Plane MCP server loads many tool schemas at session start — in clients that eagerly load MCP tools (Claude Desktop) that cost is paid whether or not an agent ever touches Plane. In clients that defer via ToolSearch, fetching tool schemas mid-session still accumulates context. A shell CLI with lazy, grep-based help pays zero token cost until called, and returns bounded help text at each step.

## Scope (v1)

Tier-1 hand-wrapped resources: **projects, issues, cycles, comments, time-entries, labels, states.** Each exposes the common CRUD + list actions with paging, filters, and dry-run on destructive verbs. See `plane help <resource>` after install.

Meta-commands: `plane help [resource]`, `plane version`, `plane doctor`, `plane resolve`.

Everything else *will* be reachable through `plane api <METHOD> <path>` — a generic escape hatch with dry-run on all non-GET methods. That path is stubbed in the dispatcher and lands in Unit 7.

## Requirements

- `bash` ≥ 4 (for the `plane` CLI)
- `curl`
- `jq` ≥ 1.6

On fresh macOS, the system bash is 3.2. `install.sh` itself runs under 3.2 and will tell you to `brew install bash` if the runtime is missing.

## Install

```bash
# 1. Create the shared config
cp docs/example-plane-config ~/.claude/.plane
chmod 600 ~/.claude/.plane
$EDITOR ~/.claude/.plane   # set workspace_slug, api_url, api_key_env

# 2. Export your Plane API key under whatever name api_key_env points at
export PLANE_API_KEY=plane_api_...

# 3. Install
./install.sh           # copy mode (default)
./install.sh --symlink # symlink mode (for maintainers)

# Uninstall
./uninstall.sh
```

The installer refuses to run if the source repo lives outside `$HOME`, if `~/.claude/.plane` is missing, or if the runtime bash is too old and no brewed bash is available. Re-running at the same git SHA is a no-op.

## Config

`~/.claude/.plane` is a plain `key=value` file shared with the `plane-time-tracking` skill. Both skills read it, neither writes it. See `docs/contract-claude-plane.md` for the full contract.

```
workspace_slug=acme
api_url=https://plane.acme.com
api_key_env=PLANE_API_KEY
```

The API key itself lives in your shell environment — the config file only records *which* env var to read, never the value.

## Exit codes

See `docs/exit-codes.md`. Notable: **exit 7 is dry-run, not failure** — agents can treat it as an intentional no-op when a destructive verb was invoked without `--execute`.

## Layout

```
bin/plane                # dispatcher: global-flag parsing, lazy help, meta + resource routing
lib/
  _core.sh               # HTTP, config, preflight, retry, exit-code mapping
  _parse.sh              # shared arg/flag parsing helpers
  _resource.sh           # shared per-resource action plumbing
  _endpoint_map.sh       # hand-authored path table from the captured OpenAPI spec
  _help.sh               # grep-based lazy help (reads # Summary: headers)
  projects.sh issues.sh cycles.sh comments.sh \
    time-entries.sh labels.sh states.sh       # Tier-1 resource wrappers
  doctor.sh version.sh resolve.sh             # meta-commands
  summaries/*.jq         # per-resource jq projections for human-readable output
docs/
  exit-codes.md
  contract-claude-plane.md
  destructive-actions.md
  premise-validation.md
  smoke-checklist.md
  example-plane-config
  plane-openapi-<ts>.yaml # snapshot of the upstream spec the endpoint map was built from
  plans/                 # active plan
  brainstorms/           # requirements brainstorm
test/                    # bash test runner + fixtures + per-unit suites
install.sh uninstall.sh
SKILL.md                 # skill manifest (Unit 1 placeholder — Unit 8 replaces with agent-facing reference)
```

## Development

Tests are plain bash. `test/run.sh` first syntax-checks every shell file under `bin/`, `lib/`, `test/`, plus `install.sh` / `uninstall.sh`, then runs each `test/*.test.sh` in a clean subshell with a sandboxed `$PATH` whose `curl` is shimmed by `test/lib/mock_curl.sh`. Fixtures live under `test/fixtures/`.

```bash
./test/run.sh
```
