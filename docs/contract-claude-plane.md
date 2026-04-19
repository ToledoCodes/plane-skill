# `~/.claude/.plane` — Shared Config Contract

**Audience:** maintainers of any Claude Code skill that talks to Plane.so.
**Status:** active, versioned additively.

## Purpose

Two independent skills currently consume Plane:

- `plane` (this repo) — the Plane.so REST CLI.
- `plane-time-tracking` (`~/.claude/skills/plane-time-tracking/`) — session time tracker.

They deliberately do **not** share code. They share one config file so the user configures Plane once and both work.

## Location

`~/.claude/.plane`

Never inside a repo. Never under version control. Mode `0600`. Anything that writes it must enforce the mode.

## File format

Plain `key=value`, one per line. `#` starts a line comment. No quoting. No multi-line values. Unknown keys are ignored by well-behaved readers.

## Current keys (v1)

| Key              | Type   | Required | Meaning                                                                                                |
|------------------|--------|----------|--------------------------------------------------------------------------------------------------------|
| `workspace_slug` | string | yes      | Plane workspace slug (e.g. `acme`). Appears in every workspace-scoped URL.                              |
| `api_url`        | string | yes      | Base URL of the Plane instance (e.g. `https://api.plane.so` or self-hosted). **HTTPS required.**       |
| `api_key_env`    | string | yes      | **Name** of the environment variable that holds the Plane API key. Not the key itself.                  |

The API key lives in the user's shell environment, not this file. The file records *which* env var to read.

### Example

```
workspace_slug=acme
api_url=https://plane.acme.com
api_key_env=PLANE_API_KEY
```

And in the user's `~/.zshrc` or equivalent:

```
export PLANE_API_KEY=plane_api_...
```

## Contract rules

These are load-bearing. Any skill that touches this file must follow them.

1. **Both skills read. Neither writes.** If either skill needs to mutate config, the user edits the file manually.
2. **Additive-only compatibility.** A new skill may *add* keys it needs. No skill may rename or remove an existing key. The v1 key set (`workspace_slug`, `api_url`, `api_key_env`) is stable.
3. **Unknown keys are ignored.** A reader that does not recognize a key reads past it. This is how additive evolution stays safe.
4. **The API key is named, never stored.** Every reader resolves the key from `printenv "$api_key_env"`. It never appears in this file, in argv, or in command history.
5. **HTTPS only.** Readers reject `http://` values in `api_url` with a config error.
6. **Mode 0600 expected.** Readers may warn on broader modes; they should not silently rewrite permissions (the user owns this file).

## Adding a key (future)

- Prefix with the skill name if the key is skill-specific (e.g. `timetracking_default_project`). Plain keys are reserved for cross-skill use.
- Document here in a new row of the key table. Include type, required/optional, default, and which skill(s) read it.
- Bump the v-label in this doc (v1 → v2) only when a key becomes *required* across skills.

## Non-goals

- Not a lockstep release protocol. Skills evolve independently; the contract does.
- Not a migration story. The v1 key set is stable and not planned to change.
- Not consolidation. Merging the two skills into one is explicitly out of scope.
