---
date: 2026-04-19
topic: plane-skill
---

# `plane` Skill (Plane.so REST CLI)

## Problem Frame

Claude Code sessions that interact with Plane.so currently load the `plane-mcp-server` MCP tools, which adds a non-trivial number of tool schemas to the context window at session start. A lighter-weight alternative — a shell CLI that exposes the full Plane REST API surface — would let agents use Plane without paying MCP loading cost upfront.

**MCP alternatives considered and rejected:** selective MCP tool loading and ToolSearch-style lazy loading were considered. Both still require an MCP runtime and per-server config on every machine; a portable, zero-runtime shell skill wins on simplicity and install cost. The premise (MCP schema load is meaningfully expensive) is nonetheless validated before v1 ships — see Success Criteria.

**Terminology (used consistently below):**
- **Plane.so** — the product / SaaS.
- **Plane REST API** — the HTTP service at `api_url`, documented at `developers.plane.so/api-reference/`.
- **`plane` skill** — the deliverable in this repo.
- **`plane` CLI** — the binary installed by the skill.

The skill is a self-contained git repo deployable to `~/.claude/skills/plane/` on any macOS/Linux machine, shipping a single `plane` CLI binary that covers the Plane REST API via shell + `curl` + `jq`.

## Requirements

**API coverage**
- R1. The skill MUST provide subcommands for the Plane REST API surface documented at `developers.plane.so/api-reference/` as of the build date. At minimum: projects, issues (work items), cycles, modules, labels, states, pages (project + workspace), time entries / work logs, comments, links, work item types, work item properties, work item relations, initiatives, epics, milestones, intake work items, workspace members, workspace features, and admin/meta endpoints (`me`, workspace/project features).
- R1a. Coverage is stratified into two tiers for v1 (Tier 2 deferred post-v1 per document-review):
  - **Tier 1 (wrapped)** — first-class subcommand with per-resource args, summary formatter, and destructive-verb dry-run. v1 T1 set: **projects, issues, cycles, comments, time-entries, labels, states** (exactly 7; matches the high-traffic set).
  - **Tier 3 (escape hatch only)** — accessible via `plane api <METHOD> <path>`. Covers every other Plane resource (pages, links, work-item-types, work-item-properties, work-item-relations, initiatives, epics, milestones, intake, members, features, modules, and anything future).
  - **Tier 2 (deferred):** originally envisioned as thin data-driven wrappers with `plane <resource> <action> --data @file` UX. Document-review found this UX is identical to `plane api` with a prettier name, costing ~11 libs + fixtures + help-tree tokens for near-zero marginal value. Deferred; will be added reactively per Rule of Three (after a resource is accessed via escape hatch ≥ 3 times in real workflows, consider promoting it to Tier 1).
- R2. The skill MUST expose a generic escape hatch: `plane api <METHOD> <path> [--data JSON|@file] [--query KEY=VAL ...]`. Paths starting with `/api/v1/` are used verbatim; other paths MUST be resolved under `/api/v1/workspaces/<workspace_slug>/`. `--data` MUST be validated client-side as JSON (via `jq -e type`) before any network call; invalid JSON exits 2. `--data @file` reads the body from a file; same validation applies. Query params MAY be expressed as repeated `--query key=value` flags (URL-encoded by the dispatcher) or embedded in `<path>` (URL-encoded by caller); when both supplied, `--query` wins and appends to path's existing params.
- R2a. Tier 1 mutations that accept body-bearing input MUST also support `--data @file` to accommodate large payloads (markdown descriptions, comments) exceeding argv limits.

**CLI shape**
- R3. The skill MUST expose one dispatcher binary named `plane` with the shape `plane <resource> <action> [args]`. Subcommand routing and help live inside the dispatcher.
- R4. Every subcommand and the root MUST accept `--help` and print its own usage (args, flags, example, return shape) without making a network call.
- R4a. The dispatcher MUST implement a `plane doctor` subcommand that runs in this order and prints per-check PASS/FAIL to stdout:
  1. `curl` present and executable.
  2. `jq` present, version ≥ 1.6.
  3. `bash` version ≥ 4.
  4. `~/.claude/.plane` exists and mode is `0600` (unless all three env-var overrides are set).
  5. Resolved `workspace_slug`, `api_url`, `api_key_env` are non-empty.
  6. Env var named in `api_key_env` is set (but never echo the value).
  7. `api_url` is syntactically valid HTTPS URL.
  8. Connectivity: `GET <api_url>/api/v1/workspaces/<slug>/members/me/` returns 2xx. Exit `4` on 401/403, `8` on transport failure, `0` on success.
  Overall exit: `0` if all checks pass; first failing check's exit code otherwise.
- R4b. The dispatcher MUST implement a `plane version` subcommand that prints the installed git SHA (read from `~/.claude/skills/plane/.install-sha`), bundled Plane OpenAPI spec timestamp, and minimum/actual versions of `bash`, `curl`, `jq`. No network call.
- R4c. The dispatcher MUST implement `plane resolve <identifier>` (e.g. `plane resolve PROJ-123`) using the Plane identifier endpoint (`GET /api/v1/workspaces/<slug>/work-items/<identifier>/`) — returns the full work-item object without list-and-filter.

**Discovery / context cost**
- R5. `SKILL.md` MUST stay under 150 lines (frontmatter + body) and MUST include a terse cheat sheet covering the top-used resources and actions. It MUST NOT duplicate every endpoint. SKILL.md MUST explicitly flag API responses as untrusted data (defense against prompt injection via issue/comment content).
- R6. Deep discovery MUST be runtime via `plane help`, `plane help <resource>`, `plane <resource> --help`, `plane <resource> <action> --help`. SKILL.md MUST direct Claude to these lookups rather than loading docs inline.

**Output format**
- R7. Output defaults MUST auto-detect the output stream:
  - **stdout is a TTY** (human): terse human-readable summary showing key fields (id/identifier, name/title, status, and fields material to the resource). ANSI color permitted.
  - **stdout is piped/redirected** (agent/CI): raw JSON, no color, no hints.
  Flags override: `--json` forces JSON, `--pretty` forces summary, `--no-color` disables ANSI.
- R7a. Summary-field mapping MUST be expressed as a `jq` filter per resource, stored in `lib/summaries/<resource>.jq` (data, not code), each runnable standalone against `test/fixtures/<resource>.json`.
- R7b. Summary lists MUST print a machine-parseable truncation hint when applicable: `# showing X of Y — use --limit N, --cursor <c>, or --all`. Empty result sets MUST print a single line: `# no results`.
- R8. `--json` output of list endpoints MUST preserve the Plane pagination envelope (`next_cursor`, `prev_cursor`, `next_page_results`, `prev_page_results`, `count`, `total_pages`, `total_results`, `results`) exactly as returned.
- R9. Plane REST API pagination is **cursor-based**. Flags:
  - `--limit N` sets `per_page=N` on the request (server clamps at 100; values > 100 MUST be clamped client-side with a stderr warning).
  - `--cursor <opaque>` passes the opaque cursor value to the API unchanged (obtained from a previous response's `next_cursor` / `prev_cursor`).
  - `--all` auto-paginates using `next_cursor` until exhaustion, with a safety cap of **500 items total per invocation**. When the cap is reached before exhaustion, exit code MUST be `0` but a machine-parseable notice MUST print to stderr: `# --all cap (500) reached; use --cursor <next_cursor_value> to continue`.
  - `--page N` is explicitly NOT supported (Plane uses cursors); passing it exits 2 with a hint pointing to `--cursor`.
- R9a. String rendering in summary mode MUST strip ANSI escapes and control characters from API-sourced fields to blunt prompt injection via issue titles/comments.

**Safety / mutations**
- R10. Destructive actions — **delete, archive, bulk delete, bulk update, remove_relation, transfer_cycle_work_items, workspace-scope DELETEs** — MUST default to dry-run. Non-destructive mutations (create, update, single add) execute by default.
- R10a. Dry-run MUST print:
  1. HTTP method, URL, request body.
  2. A one-line human-readable summary (e.g., `Would delete cycle "Sprint 42"`).
  3. The literal line `Add --execute to confirm.`
  Dry-run MUST NOT perform any network call. `Authorization` / API-key header values MUST be redacted (`Authorization: <redacted>`).
- R10b. For request bodies > 2KB, or containing fields matching `(?i)token|password|secret|key|authorization`, dry-run MUST truncate/redact those fields.
- R10c. For multipart/file-upload payloads, dry-run MUST print content-type, filename, and size — never raw bytes.
- R11. For destructive actions, `--execute` MUST be required to perform the mutation. No prompt. Exit code on dry-run MUST be `7` so callers detect "forgot --execute" as a first-class condition.
- R11a. Planning MUST produce an explicit classification of every Tier 1 / Tier 2 subcommand as destructive (dry-run default) or non-destructive (execute default). The classification lives in `docs/destructive-actions.md`.
- R12. The `plane api` escape hatch MUST honor dry-run by default for **all non-GET methods** (POST, PUT, PATCH, DELETE). `--execute` required. Unlike T1 wrappers (where create/update execute by default because we know the verb is non-destructive), the escape hatch can target arbitrary paths including admin endpoints, so a generic dry-run gate is the correct safety posture. Redaction rules (R10a-c) apply to dry-run output. Exit 7 on dry-run.

**Configuration & secrets**
- R13. The skill MUST read config from `~/.claude/.plane` in the format shared with `plane-time-tracking`: `workspace_slug=`, `api_url=`, `api_key_env=`. The file MUST be enforced to mode `0600`; `install.sh` MUST set this on creation and every command MUST warn on startup if permissions are broader.
- R13a. The `~/.claude/.plane` format is a **shared contract** with `plane-time-tracking`. This repo MUST include `docs/contract-claude-plane.md` describing the format, ownership (read-only from both skills; created by `install.sh`), and a compatibility policy (keys may be added, never removed or renamed). Both skills read; neither writes during normal operation.
- R14. The skill MUST resolve the API key from the environment variable named in `api_key_env` (e.g. `PLANE_API_KEY`) and send it as HTTP header `X-API-Key: <key>` (exact capitalization per Plane docs). The key MUST be passed to `curl` via `curl --config -` on stdin (`header = "X-API-Key: ..."` form) — NEVER on the command line (argv), so it never appears in `ps` / `/proc/<pid>/cmdline`. The key MUST NEVER be logged, printed, or echoed to stdout/stderr.
- R15. Per-invocation overrides via env vars: `PLANE_WORKSPACE_SLUG`, `PLANE_API_URL`, `PLANE_API_KEY`. Resolution order per field: CLI flag > env var > config file. CLI flags `--workspace <slug>` and `--api-url <url>` MUST be accepted at the dispatcher level (before subcommand) so agents can target specific workspaces per call without exporting env vars. If all three fields are resolved (via any combination of flag/env/file), the config file is not required; its absence MUST NOT cause exit 3. `PLANE_API_URL` / `--api-url` MUST be validated: scheme MUST be `https` (reject `http://`), host MUST be non-empty; invalid URL exits 3.
- R15a. TLS: `curl` MUST always run with `--fail-with-body` and MUST NEVER be invoked with `-k` / `--insecure`. Custom CA bundles are permitted via the standard `CURL_CA_BUNDLE` env var only.

**Error handling & reliability**
- R16. On HTTP 429, the skill MUST compute wait time as `max(1, X-RateLimit-Reset − now())` (epoch seconds), capped at 60s. If the header is absent (unlikely for Plane Cloud; possible for self-hosted), honor `Retry-After` if present, else fall back to flat 4s backoff. Maximum 3 retries. If still 429 after retries, exit `5` with the Plane response body on stderr.
- R16a. On HTTP 5xx, idempotent methods (GET, HEAD, PUT, DELETE) MUST retry once with 2s backoff. Non-idempotent methods (POST, PATCH) MUST NOT retry automatically — retrying risks double-create. If still 5xx after the allowed retry, exit `6` with the Plane response body on stderr.
- R16b. Transport-layer failures MUST surface distinctly. `curl` exit codes 6 (DNS failure), 7 (connect failure), 28 (timeout), 35/60 (TLS handshake/cert), 56 (recv failure) MUST map to exit code `8` with a human-readable message naming the failure class on stderr. `curl` MUST be invoked with `--connect-timeout 10` and `--max-time 60` by default; both overridable via `PLANE_CONNECT_TIMEOUT` / `PLANE_MAX_TIME`.
- R16c. HTTP 3xx redirects MUST NOT be followed silently. If Plane returns a 3xx, treat as error (exit 1) unless explicitly opted in via `--follow-redirects`.
- R17. Non-2xx responses MUST print status code + response body to stderr and exit non-zero per the code table (R18). Summary mode MUST NOT silently drop error bodies. HTTP 400/422 → exit `2` (bad request). HTTP 404 → exit `9`. HTTP 409 → exit `10`. Other 4xx → exit `1`.
- R18. Exit codes (stable contract, documented in SKILL.md):
  - `0` success
  - `1` generic runtime error (unmapped 4xx, unknown failure)
  - `2` bad usage / arg parse / invalid `--data` JSON / HTTP 400 / HTTP 422
  - `3` not configured (config file missing AND env vars not fully set; or invalid `PLANE_API_URL`; or required env var named in `api_key_env` is unset — error message MUST name the missing field)
  - `4` API auth rejected (HTTP 401 or 403 from Plane)
  - `5` rate-limited after retries (HTTP 429 exhausted)
  - `6` server error (5xx after retry policy)
  - `7` dry-run (destructive command ran without `--execute`)
  - `8` transport failure (DNS, connect, TLS, timeout — `curl` exit codes 6/7/28/35/60/56)
  - `9` resource not found (HTTP 404)
  - `10` resource conflict (HTTP 409)

**Runtime dependencies**
- R19. The skill MUST depend on `curl` (any) and `jq` **≥ 1.6** only. First invocation MUST preflight both (presence + `jq` version) and print a precise install hint if either is missing or too old.
- R19a. Request bodies MUST be built by piping through `jq -n --arg` / `--argjson` — NEVER via `printf` or string concatenation — so embedded quotes, newlines, and Unicode in user-supplied values (comments, descriptions, names) are encoded correctly.
- R20. The skill MUST NOT require Node, Python, Go, or any runtime beyond POSIX shell + curl + jq at install or run time.
- R20b. **One-shot OpenAPI spec capture (maintainer action, v1 setup).** Plane Cloud does NOT publish a public OpenAPI spec; self-hosted Plane v2.5.1+ exposes one via Swagger UI. The maintainer probes common Swagger paths (`/api/schema/`, `/api/v1/schema/`, `/api/swagger/`, `/api/docs/`, `/schema.yaml`, `/openapi.yaml`, `/openapi.json`) on `https://plan.toledo.codes/` via `curl` and commits whatever YAML/JSON returns 2xx to `docs/plane-openapi-<ISO8601>.yaml` as a reference artifact. If no path returns the spec, the maintainer uses Plane's published HTML docs as the authoritative reference. **No code generation pipeline.** The resource → endpoint map (`lib/_endpoint_map.sh`) is hand-authored from the captured spec or docs — ~40-60 entries across 7 T1 resources, ~2 hours of work. No Python, no Node, no generator of any kind. Keeps the skill's "bash + curl + jq" identity clean end-to-end (including maintainer tooling).
- R20c. **Resource scaffolder deferred post-v1.** No v1 resource needs the scaffolder (all 7 T1 resources are authored directly in Unit 6). When the first post-v1 resource is added (e.g., promoting a T3 escape-hatch pattern to Tier 1 because it's used ≥ 3 times), the scaffolder is built then — as a pure-bash template expander under `tools/scaffold.sh`, zero runtime deps beyond bash.
- R20a. Bash floor: **bash 4+** (the skill MAY install via `brew install bash` on macOS; the install script MUST detect and warn if `bash` on PATH is older). Rationale: associative arrays are needed for the dispatcher and summary maps, which are infeasible in bash 3.2.

**Packaging / install**
- R21. The canonical source MUST be a single self-contained git repo (`~/Projects/PlaneSkill`), cloneable and usable on any macOS/Linux machine without build steps at install time.
- R22. The repo MUST include `install.sh` that copies (or symlinks, via `--symlink`) the skill into `~/.claude/skills/plane/`. `install.sh` MUST:
  - Be idempotent.
  - Resolve the source repo path via `readlink -f` / `realpath` and refuse to install if the resolved path is outside the invoking user's `$HOME`.
  - Refuse to scaffold `~/.claude/.plane`; if the config file is missing, print setup instructions and exit non-zero (user opts in explicitly).
  - Record the installed git commit SHA in `~/.claude/skills/plane/.install-sha`.
- R23. The repo MUST include `uninstall.sh` that resolves the target path via `readlink -f` and asserts it begins with `$HOME/.claude/skills/plane/` before any `rm -rf`. Refuses to touch anything else.
- R24. `SKILL.md` frontmatter MUST name the skill `plane` and MUST describe trigger phrases so the Skill tool can surface it.

**Testing**
- R25. The repo MUST include `test/` with unit-level bash tests for pure logic: argument parsing, URL construction, `jq` filter output shape against fixture JSON, exit code mapping, dry-run output formatting (including redaction), config resolution (env precedence + missing file cases), and escape-hatch path resolution.
- R26. Tests MUST run with a single `./test/run.sh` — plain bash + `diff` against golden fixtures in `test/fixtures/`. No external test framework (no `bats-core`, no Node). No network.
- R27. Live API integration tests are out of scope for v1. The repo MUST include `docs/smoke-checklist.md` — a manual checklist the maintainer runs against a real workspace before each release (list + read + dry-run + one execute for 3-5 representative resources).

## Success Criteria

- Session-start context budget for the skill is `SKILL.md` (< 150 lines) only — no schemas, no preloaded tool list.
- An agent can discover any Plane REST API operation through `plane help*` lookups without the human pasting docs.
- An agent completes the reference workflow — "find open issues in cycle X, add a comment to each, log a time entry" — using only `plane` subcommands.
- **Premise validation gate (v1 blocker):** Before v1 ships, measure (a) tokens added by loading `plane-mcp-server` on this machine with default tool loading, (b) tokens consumed by the reference workflow end-to-end via `plane` skill (SKILL.md + help lookups + dry-run + execute calls for 5 issues), (c) tokens consumed by the same workflow via `plane-mcp-server`. Target: (b) ≤ **30%** of (c). If the skill can't clear this bar, v1 does not ship; either the skill or the premise is wrong. Record results in `docs/premise-validation.md`.
- An agent that forgets `--execute` produces a dry-run transcript and exit code 7 — never an accidental mutation.
- The repo clones, installs on a second machine with `./install.sh`, and works against that user's `~/.claude/.plane` config without edits to the skill.
- No API key value ever appears in `ps`, shell history, logs, or dry-run output.

## Scope Boundaries

- No live / integration tests against a real Plane workspace in v1 (manual smoke checklist only).
- No TUI, interactive wizard, or REPL.
- No shell completion in v1.
- No merging or replacement of `plane-time-tracking`, now or later. The two skills stay independent permanently. Overlap (time entries) is accepted as the cost of keeping each skill simple and independently versioned. They share `~/.claude/.plane` via the written contract in R13a — that is the entire coupling.
- No local caching of Plane responses.
- No wrapper around the Plane MCP server; this is a parallel path against the REST API.
- No new config file formats.
- No telemetry, usage reporting, or outbound channel other than the configured Plane REST API.
- No file-upload (multipart) Tier 1 wrappers in v1 — file attachments reachable via `plane api` escape hatch only.

## Key Decisions

- **Dispatcher over many scripts** — single `plane` binary, subcommand routing. (R3, R6.)
- **Dry-run default only for destructive verbs** — delete/archive/bulk-delete/bulk-update/remove-relation default to dry-run; create/update execute by default. Exit code 7 on dry-run lets agents detect "forgot --execute". (R10-R12.)
- **TTY-aware output defaults** — interactive terminal gets summary + color; pipe/redirect gets raw JSON. Explicit `--json` / `--pretty` override. (R7.)
- **Small pagination (20), opt-in `--all`** — token-sensitive default. (R7b, R9.)
- **curl + jq ≥ 1.6 + bash 4+, one-shot OpenAPI bootstrap + resource scaffolder** — no runtime language dependency on end-user machines; OpenAPI spec used once at project bootstrap to emit starter bash stubs, then hand-maintained. New resources post-bootstrap added via a zero-runtime `tools/scaffold.sh` template expander. No ongoing codegen pipeline. (R19, R20, R20a, R20b, R20c.)
- **Skill + CLI named `plane`** — no collision with `plane-time-tracking`. (R24.)
- **Config reuse with explicit shared contract** — share `~/.claude/.plane` with `plane-time-tracking` via a written compatibility policy. The two skills stay permanently independent otherwise. (R13, R13a.)
- **Coverage tiers (T1/T2/T3)** — hand-wrapping every endpoint is a non-goal; generic dispatcher + escape hatch cover the long tail. (R1a, R2.)
- **Security-by-default on key handling** — key via stdin/config-file to curl (never argv), config file mode 0600, HTTPS-only, TLS verification always on, key/body redaction in dry-run. (R14, R15, R15a, R10a.)
- **Honor `Retry-After`, cap 60s, 3 retries** — cooperate with server. (R16.)
- **Premise validation is a v1 ship gate** — skill must demonstrate ≤ 30% of MCP baseline tokens on reference workflow before v1 ships. MCP alternatives (selective load, ToolSearch) formally rejected on simplicity/portability grounds. (Success Criteria.)

## Dependencies / Assumptions

- Assumes `~/.claude/.plane` provides `workspace_slug`, `api_url`, `api_key_env`, OR all three override env vars are set.
- Assumes Plane REST API base path follows `<api_url>/api/v1/workspaces/<slug>/...` for workspace-scoped endpoints. Unverified against full endpoint list; planning MUST enumerate.
- Pagination parameter names (`per_page`, `page`, or cursor-based) are **not** uniform across Plane resources. Planning MUST verify per resource and map to `--limit`/`--page`/`--all`.
- Assumes `curl`, `jq ≥ 1.6`, and `bash ≥ 4` on target machines. macOS users may need `brew install bash jq`. Note that `install.sh` itself MUST remain bash-3.2 compatible so it can run on a fresh macOS before `brew install bash` — only the `plane` CLI requires bash 4.
- Assumes Plane's 429 responses include `X-RateLimit-Remaining` and `X-RateLimit-Reset` headers. `Retry-After` is NOT documented for Plane Cloud; treated as fallback-only.
- Assumes pagination is uniform cursor-based across all list endpoints (documented). Planning smoke-checks one non-trivial list endpoint to verify.
- Assumes the user's Plane API key is scoped appropriately; the skill does not enforce token scope.
- Assumes file attachments are out of scope for Tier 1 (two-step presigned S3 flow); agents use escape hatch if needed.

## Outstanding Questions

### Resolve Before Planning

*(None — the 7 open product questions from review have been resolved and are reflected in the decisions and requirements above.)*

### Deferred to Planning

- [Affects R1, R1a][Needs research] Enumerate every Plane REST endpoint from `developers.plane.so/api-reference/` and assign each to Tier 1 / Tier 2 / Tier 3. Output is a coverage matrix table.
- [Affects R9][Needs research] Per-resource pagination contract (param names, max page size, cursor vs offset). Output is a pagination map used by the dispatcher.
- [Affects R3][Technical] Dispatcher internal structure — one monolithic `bin/plane` vs `bin/plane` + `lib/<resource>.sh` sourced on demand. Lean toward the latter for per-resource isolation and test scope.
- [Affects R7][Technical] Exact summary-field jq filter shape per resource. Bound by R7 (one file per resource under `lib/summaries/`).
- [Affects R20b][Technical] Bootstrap generator implementation language (Python/Node/Go — maintainer's choice; runs once). Where to capture the Plane OpenAPI spec from, how to pin the version, what the output directory layout is.
- [Affects R20c][Technical] Template shape for `tools/scaffold.sh` — what placeholders the templates use, where the resource-endpoint map entry is added.
- [Affects R22][Technical] Install script's approach to shell version detection on macOS (`/usr/bin/bash` = 3.2 vs `/opt/homebrew/bin/bash`).
- [Affects R25][Technical] Test fixture sourcing — capture real API responses once, commit to `test/fixtures/`. Decide in-tree vs separate fixtures repo.
- [Affects R10, R11a][Technical] Enumerate the destructive verb list per resource and commit to `docs/destructive-actions.md`. Base set: `delete`, `archive`, `bulk delete/update`, `remove-relation`, `transfer-cycle-work-items`, workspace-scope DELETEs.

## Resolved product decisions

Seven product-level questions from document review, now locked:

1. **Premise validation is a v1 ship gate** — MCP token cost measured before release; skill must hit ≤ 30% of that baseline on the reference workflow. (See Success Criteria.)
2. **MCP alternatives formally rejected** — selective tool loading / ToolSearch still require MCP runtime + per-server config; shell skill wins on portability. (See Problem Frame.)
3. **Dry-run only for destructive verbs** — delete/archive/bulk/remove-relation default to dry-run; create/update execute by default. (R10-R11a.)
4. **TTY-aware output defaults** — human terminal → summary + color; piped/redirected → raw JSON. (R7.)
5. **Token budget ≤ 30% of MCP baseline** (stricter than typical "meaningful improvement"). (Success Criteria.)
6. **Two skills stay independent permanently** — `plane-time-tracking` will not be rewritten as a wrapper. Shared config is the entire coupling. (Scope Boundaries, R13a.)
7. **One-shot OpenAPI bootstrap + ongoing resource scaffolder** — OpenAPI spec used once to emit starter stubs (then hand-maintained); `tools/scaffold.sh` handles new resources via pure-bash templates. No ongoing codegen pipeline; end-user machines stay runtime-free. (R20, R20b, R20c.)

## Next Steps

-> `/ce:plan` for structured implementation planning.
