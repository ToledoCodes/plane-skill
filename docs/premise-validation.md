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

---

## Unit 3 findings — live probes against `plan.toledo.codes`

Captured 2026-04-19 against workspace `ojtech`. Only read-only GETs; no destructive verbs exercised.

### OpenAPI schema

- **Canonical path:** `/api/schema/` (trailing slash required; `/api/schema` 301-redirects). Probed `/api/schema/` first, hit 200 directly.
- **Content-Type:** `application/vnd.oai.openapi; charset=utf-8` (YAML body, OpenAPI 3.0.3).
- **Size:** 499,644 bytes, 15,843 lines, 65 unique paths, 128 operations.
- **Committed:** `docs/plane-openapi-2026-04-19T191402Z.yaml` with a leading comment block naming the source, timestamp, and "reference only" marker.
- **Auth scheme** (per spec and confirmed by probes): `ApiKeyAuthentication` — header `X-API-Key`. Matches prior skill and plan design.

### Pagination envelope — uniform across every list endpoint probed

All six T1-relevant list endpoints returned the **exact same** top-level keys:

```
grouped_by, sub_grouped_by, total_count, next_cursor, prev_cursor,
next_page_results, prev_page_results, count, total_pages, total_results,
extra_stats, results
```

Probed: `/projects/`, `/projects/{id}/issues/`, `/projects/{id}/labels/`, `/projects/{id}/cycles/`, `/projects/{id}/states/`, `/projects/{id}/issues/{iid}/comments/`, `/projects/{id}/time-entries/`. All 200; all identical shape.

- **Pagination params (canonical, per schema):** `cursor=<str>` + `per_page=<int>` (default 20, max 100).
- **Cursor format:** `'page_size:page_number:offset'` (e.g. `'20:1:0'`). Server-opaque from the CLI's perspective — agents pass it back verbatim.
- **CLI mapping decision:** `--limit N` → `per_page=N`. `--cursor S` → `cursor=S`. `--all` iterates `next_cursor` until empty. `--page` explicitly rejected with a hint.
- **Deviation from plan:** plan drafts showed `--limit` as the param name — server uses `per_page`. CLI flag stays `--limit` (user-facing ergonomics); transport layer translates.

### Rate-limit headers

No `X-RateLimit-*` or `Retry-After` headers observed on 2xx responses. Natural baseline — we did not force a 429 (out of scope for non-destructive probing; would hammer the sandbox). Plan's 429-retry logic consumes these headers only when Plane actually emits them, so "header may be absent on normal responses" is expected and handled (`_core_parse_retry_after` falls back to 4s).

### Identifier resolution

Real issue in sandbox: project `Municipal Post` / identifier `MUNI` / sequence `16` → `MUNI-16`.

Both candidate paths returned **200** with identical body shape:

- `GET /workspaces/ojtech/work-items/MUNI-16/` — 200 ✓ (documented path)
- `GET /workspaces/ojtech/issues/MUNI-16/` — 200 ✓ (prior-skill path)

**Decision:** use `/workspaces/<slug>/issues/<identifier>/` in `lib/resolve.sh` (Unit 4). Prior skill already uses this; both work; keep the surface consistent with prior art. If a future Plane release removes the alias, swap to `work-items/` and re-probe.

Note: Plane issue objects do NOT carry the `project_identifier` short code. The CLI's `plane resolve PROJ-123` input is parsed as `<IDENTIFIER>-<SEQ>` and passed through as a URL segment; resolution happens server-side.

### Destructive-verb cascades — not probed

Plan calls for a `DELETE /projects/<uuid>/` probe on a throwaway project to record cascade behavior. **Skipped** per user instruction (non-destructive probing only). Consequences:

- `docs/destructive-actions.md` stays at "TBD" for cascade annotations.
- Unit 6 will either probe on a disposable project at author-time, or classify conservatively (assume cascade; require `--execute`; document behavior if probed later).

### POST idempotency — not probed

Same reason. Plane's POST idempotency guarantees remain unknown. Plan's conservative default (`POST/PATCH do not retry on 5xx`) is already the right call regardless; the `PLANE_RETRY_NONIDEMPOTENT=1` escape hatch exists for callers who know their payload is safe.

### Path inventory captured

All methods × paths for T1 resources extracted from the spec into the endpoint-map authoring notes. Notable findings:

- Plane exposes **both** `/issues/` and `/work-items/` under project scope as aliases. CLI uses `issues`.
- `POST /projects/{id}/archive/` + `DELETE /projects/{id}/archive/` — archive and unarchive share the URL.
- **No `bulk-create` or `bulk-delete` endpoints for time-entries** in the spec. Plan Unit 6 draft mentioned them; those actions are not available in v1 of Plane's public API and will be dropped from Unit 6 scope (use repeated single calls or `plane api` loop).
- `cycles` has first-class sub-resources: `cycle-issues` (add/remove) and `transfer-issues` — matches plan Unit 6 expectations.
