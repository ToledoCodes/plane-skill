#!/usr/bin/env bash
# Summary: manage Plane cycles and their work-item membership.
# Usage:   plane cycles <action> [args]
# Actions: list, get, create, update, delete, archive,
#          list-work-items, add-work-items, remove-work-item, transfer-work-items
#
# Unit 4 stub — full implementation lands in Unit 6.
[ "${__PLANE_RESOURCE_CYCLES_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_CYCLES_LOADED=1

_help_resource_cycles() {
  cat <<'EOF'
plane cycles — manage Plane cycles

Actions:
  list --project <id>                       List cycles in a project
  get --project <id> <cycle_id>             Get one cycle
  create --project <id> --name <name>       Create a cycle
  update --project <id> <cycle_id>          Update a cycle
  delete --project <id> <cycle_id>          Delete a cycle (destructive)
  archive --project <id> <cycle_id>         Archive a cycle (destructive)
  list-work-items --project <id> <cycle_id> Work items in a cycle
  add-work-items --project <id> <cycle_id>  Add work items to a cycle
  remove-work-item --project <id> <cycle_id> <issue_id>
                                            Remove a work item (destructive)
  transfer-work-items --project <id> <cycle_id>
                                            Transfer all work items to another cycle
EOF
}
