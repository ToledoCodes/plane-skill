# Destructive Actions

Verbs that require `--execute` to actually run. Without it, the CLI prints the intended request and exits 7 (dry-run).

**This file is a stub.** Final enumeration lands in Unit 6, after each T1 resource lib is built and each verb is classified against the live Plane API (cascade behavior, idempotency, reversibility).

## Classification rule

A verb is destructive if it:

- deletes a resource, or
- archives a resource in a way that removes it from default views, or
- performs a bulk mutation that would be expensive to undo.

Create/update/add are **not** destructive by default — they execute directly.

## Tightened rule for `plane api`

The escape hatch `plane api` dry-runs **all** non-GET methods (POST, PUT, PATCH, DELETE), not just DELETE. The escape hatch can hit arbitrary endpoints — a generic gate is the correct safety posture.

## Placeholder table (filled in Unit 6)

Cascade columns marked "TBD (not probed)" were deliberately NOT tested during
Unit 3 — user instruction was non-destructive probing only. Unit 6 will either
re-probe on a disposable project or classify conservatively (default to
destructive; require `--execute`; document observed cascade post-probe).

`time-entries bulk-delete` was dropped: no `bulk-*` endpoint exists in the
Plane v1 public API (Unit 3 spec capture). Callers use repeated single calls
or `plane api` in a loop.

| Resource     | Verb                   | Destructive? | Notes |
|--------------|------------------------|--------------|-------|
| projects     | delete                 | Yes          | Cascade TBD (not probed); classify as destructive by default |
| projects     | archive                | Yes          | Reversible via `unarchive` (DELETE same URL), but still removes from default views |
| projects     | unarchive              | No           | Restore, not a mutation that loses data |
| issues       | delete                 | Yes          | |
| cycles       | delete                 | Yes          | |
| cycles       | archive                | Yes          | |
| cycles       | remove-work-item       | Yes          | Detaches an issue from a cycle (reversible via add-work-items) |
| cycles       | transfer-work-items    | Yes          | Bulk move; significant state change even if reversible |
| labels       | delete                 | Yes          | |
| states       | delete                 | Yes          | |
| comments     | delete                 | Yes          | |
| time-entries | delete                 | Yes          | |
