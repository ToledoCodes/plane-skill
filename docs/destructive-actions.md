# Destructive Actions

Verbs that require `--execute` to actually run. Without it, the CLI emits a
dry-run transcript to stderr and exits 7.

The source of truth is `_resource_is_destructive` in `lib/_resource.sh`. This
document is a human-readable mirror — keep the two aligned.

## Classification rule

A verb is destructive if it:

- deletes a resource outright,
- archives a resource in a way that removes it from default views, or
- bulk-mutates or transfers ownership of child records.

Create / update / add default to `--execute`-not-required — they run without a flag.

## Tightened rule for `plane api`

The escape hatch dry-runs **all** non-GET methods (POST, PUT, PATCH, DELETE),
not just DELETE. The escape hatch can hit arbitrary endpoints — a generic
gate is the correct safety posture and is implemented in Unit 7.

## Tier 1 enumeration (v1, final)

| Resource     | Verb                    | Destructive? | Rationale |
|--------------|-------------------------|--------------|-----------|
| projects     | create                  | No           | Adds a new resource; reversible by delete. |
| projects     | update                  | No           | Field-level edit; reversible by re-update. |
| projects     | delete                  | Yes          | Removes the project. Cascade behavior unprobed (Unit 3 skipped live DELETE); classify conservatively. |
| projects     | archive                 | Yes          | Removes from default views; can be undone via unarchive but hides active work. |
| projects     | unarchive               | No           | Restores a prior archive; adds visibility, no data loss. |
| issues       | create / update         | No           | Standard field writes. |
| issues       | delete                  | Yes          | Removes the work item. |
| issues       | search                  | No           | Read-only. |
| cycles       | create / update         | No           | Standard field writes. |
| cycles       | delete                  | Yes          | Removes the cycle. |
| cycles       | archive                 | Yes          | Removes from default views. |
| cycles       | list-work-items         | No           | Read-only list. |
| cycles       | add-work-items          | No           | Adds membership; reversible by remove-work-item. |
| cycles       | remove-work-item        | Yes          | Detaches an issue from a cycle; reversible but material state change. |
| cycles       | transfer-work-items     | Yes          | Bulk move to another cycle; significant state shift. |
| labels       | create / update         | No           | Standard field writes. |
| labels       | delete                  | Yes          | Removes the label and unsets it across referenced issues. |
| states       | create / update         | No           | Standard field writes. |
| states       | delete                  | Yes          | Removes the state; Plane will refuse if issues still reference it. |
| comments     | create / update         | No           | Standard comment writes. |
| comments     | delete                  | Yes          | Removes the comment. |
| time-entries | create / update         | No           | Standard time-entry writes. |
| time-entries | delete                  | Yes          | Removes a time record. |
| time-entries | list / list-workspace   | No           | Read-only. |

## Deferred

- `time-entries bulk-create` / `bulk-delete`: no corresponding endpoints exist
  in Plane v1 (Unit 3 spec capture). Callers use repeated single calls or
  `plane api` in a loop.
- Resources not in v1 T1 (pages, links, work-item-types, initiatives, epics,
  milestones, intake, members, features) sit behind `plane api` and, when
  mutated, are gated by the escape hatch's all-non-GET dry-run rule.

## `--execute` contract

- Present on any destructive action: proceeds to call the API.
- Absent: the CLI prints the intended method, URL, and (redacted) body to
  stderr and exits 7.
- The flag is positional-position-insensitive: the resource action helpers
  scan all args for `--execute` before dispatching.
- `--execute` is per-invocation. There is no global "always execute" mode.
