#!/usr/bin/env bash
# Summary: manage Plane project time-entries (timer start/stop lives in plane-time-tracking).
# Usage:   plane time-entries <action> [args]
# Actions: list, get, create, update, delete, list-workspace
#
# Unit 4 stub — full implementation lands in Unit 6.
[ "${__PLANE_RESOURCE_TIME_ENTRIES_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_TIME_ENTRIES_LOADED=1

_help_resource_time_entries() {
  cat <<'EOF'
plane time-entries — manage Plane project time entries

Actions:
  list --project <id>                               List time entries in a project
  get --project <id> <time_entry_id>                Get one time entry
  create --project <id> --issue <issue_id> ...      Create a time entry
  update --project <id> <time_entry_id>             Update a time entry
  delete --project <id> <time_entry_id>             Delete a time entry (destructive)
  list-workspace                                    List time entries across the workspace

Note: the plane-time-tracking skill wraps create/update on running timers.
This resource manages the underlying records.
EOF
}
