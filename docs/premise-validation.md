# Premise Validation — MCP Baseline Measurement

**Unit 0 of `docs/plans/2026-04-19-001-feat-plane-skill-plan.md`.**

Measured: **2026-04-19**
Tooling: `claude` CLI (Claude Code headless, `claude-opus-4-7[1m]`), Plane MCP server `git+https://github.com/Actual-Reality/plane-mcp-server.git`.

## Method

Three headless sessions via `claude -p --strict-mcp-config --mcp-config <file> --output-format json "reply with exactly: OK"`. Total input tokens = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens` from the result JSON.

- **Control-A:** empty MCP config (`{"mcpServers":{}}`), default settings.
- **Treatment:** plane-only MCP config, default settings.
- **Control-B:** empty MCP config, default settings (replicate for cache noise).
- **Treatment-B:** plane-only MCP config, empty `--settings '{}'` (no plugins loaded).

Prompt held constant, 1 turn each, no tool calls made.

## Results

| Run         | MCP config  | Plugins | input | cache_creation | cache_read | **Total** |
| ----------- | ----------- | ------- | ----- | -------------- | ---------- | --------- |
| Control-A   | empty       | default | 6     | 53,506         | 0          | **53,512** |
| Treatment   | plane only  | default | 6     | 31,711         | 21,795     | **53,512** |
| Control-B   | empty       | default | 6     | 31,711         | 21,795     | **53,512** |
| Treatment-B | plane only  | none    | 6     | 31,711         | 21,795     | **53,512** |

**MCP schema-load delta (session start) = 0 tokens** (within measurement noise of a few tokens).

Cache partition shifts between runs but total processed tokens are identical — the Plane MCP server registration adds no visible schema bytes to the pre-turn context.

## Why the delta is zero

Claude Code's current harness defers MCP tool schemas via a `ToolSearch` mechanism. Tool names are visible in a deferred list (`mcp__plane__*`, etc.), but each tool's full JSONSchema is loaded only when `ToolSearch` fetches it on demand. This is the harness default — confirmed by Treatment-B (empty settings, no plugins) producing the same total as Treatment (all plugins loaded).

Observed directly in the current session's system reminder: 170+ `mcp__plane__*` tools listed as deferred with the note "schemas are NOT loaded — calling them directly will fail with InputValidationError."

## Reference workflow — not measured

The plan also asks for the reference-workflow MCP total (find open issues in a cycle, comment on each, log time, via `plane-mcp-server`). That was not executed because the session-start gate has already failed, so the number would not change the outcome of this unit. If the user wants a complete record, it can be captured later.

## Gate decision

Plan gate: *"if MCP schema-load delta < 5k tokens, pause and reconsider the project — the premise is too small to justify the build."*

**Headless `claude -p` measurement: 0 tokens delta.** But the measurement captures only one client under one mode. The `-p` CLI is not the intended runtime cost model for the premise.

**User override (2026-04-19): PROCEED.** Rationale:

1. **Claude Desktop eagerly loads MCP tool schemas.** The `-p` harness defers via ToolSearch; Claude Desktop does not. Users of Desktop (the most common Plane consumer surface) pay the full schema cost at session start. The `-p` number under-reports this use case.
2. **Mid-session schema bloat still applies under ToolSearch.** When the agent requests a Plane tool, ToolSearch loads that tool's schema into context and it stays there. Over a workflow that touches multiple resources, loaded schemas accumulate. A shell CLI with runtime `plane help <resource>` output returns bounded text and does not pin schemas.
3. The project was never scoped around the `-p` cost model; it was scoped around real interactive usage, where both of the above apply.

**Proceeding to Unit 1.** Measurement kept as record, not as gate. Re-measure at Unit 5 (mid-build) and Unit 9 (release) against a representative workflow in Claude Desktop and/or mid-session tool-fetch cost — not just `-p` session-start.

## Raw evidence

Session IDs: `26173857-5d1d-4d93-a52b-6bb37246ed2f` (Treatment-B) and prior empty/plane runs captured in shell history on 2026-04-19. Configs at `/tmp/mcp-empty.json`, `/tmp/mcp-plane-only.json`, `/tmp/empty-settings.json` during the measurement session.
