# plane — Plane.so REST CLI as a Claude Code skill

A thin shell wrapper around the [Plane.so REST API](https://developers.plane.so/api-reference/introduction), packaged as an installable Claude Code skill. Agents read and write Plane resources without loading the Plane MCP server's tool schemas; discovery happens at runtime via `plane help <resource>`.

**Status: v1 in progress.** The scaffolding below is real; the dispatcher and resource wrappers land in Units 4–6. See `docs/plans/2026-04-19-001-feat-plane-skill-plan.md`.

## Why

The Plane MCP server loads many tool schemas at session start — in clients that eagerly load MCP tools (Claude Desktop) that cost is paid whether or not an agent ever touches Plane. In clients that defer via ToolSearch, fetching tool schemas mid-session still accumulates context. A shell CLI with lazy, grep-based help pays zero token cost until called, and returns bounded help text at each step.

## Scope (v1)

Tier-1 hand-wrapped resources: **projects, issues, cycles, comments, time-entries, labels, states.**

Everything else reachable through `plane api <METHOD> <path>` — a generic escape hatch with dry-run on all non-GET methods.

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
bin/plane                # dispatcher (currently a placeholder — Unit 4 replaces)
lib/                     # resource wrappers + shared core (Units 2, 4, 6)
docs/
  exit-codes.md
  contract-claude-plane.md
  destructive-actions.md
  example-plane-config
  plans/                 # active plan + brainstorm
test/                    # bash test runner + fixtures
install.sh uninstall.sh
SKILL.md                 # skill manifest (placeholder — Unit 8 fills in)
```

## Development

Tests are plain bash with golden-file diffs. `test/run.sh` runs them all; the real runner lands in Unit 2.

```bash
./test/run.sh
```
