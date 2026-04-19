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

| Resource     | Verb                   | Destructive? | Notes |
|--------------|------------------------|--------------|-------|
| projects     | delete                 | TBD          | Check cascade to issues/cycles/modules |
| projects     | archive                | TBD          | |
| issues       | delete                 | TBD          | |
| cycles       | delete                 | TBD          | |
| cycles       | archive                | TBD          | |
| cycles       | remove-work-items      | TBD          | |
| cycles       | transfer-work-items    | TBD          | |
| labels       | delete                 | TBD          | |
| states       | delete                 | TBD          | |
| comments     | delete                 | TBD          | |
| time-entries | delete                 | TBD          | |
| time-entries | bulk-delete            | TBD          | |
