#!/usr/bin/env bash
# Summary: manage Plane issues / work items (list, get, create, update, delete, search).
# Usage:   plane issues <action> [args]
# Actions: list, get, create, update, delete, search
#
# Unit 4 stub — full implementation lands in Unit 6.
[ "${__PLANE_RESOURCE_ISSUES_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_ISSUES_LOADED=1

_help_resource_issues() {
  cat <<'EOF'
plane issues — manage Plane work items (a.k.a. issues)

Actions:
  list --project <id>                   List issues in a project
  get --project <id> <issue_id>         Get one issue (UUID, project-scoped)
  create --project <id> --name <name>   Create an issue
  update --project <id> <issue_id>      Update an issue
  delete --project <id> <issue_id>      Delete an issue (destructive — requires --execute)
  search --query <text>                 Workspace-wide issue search

To resolve a human-readable identifier (e.g. PROJ-123) to a work-item
object, use `plane resolve PROJ-123`.
EOF
}
