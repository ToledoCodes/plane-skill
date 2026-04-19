#!/usr/bin/env bash
# Summary: manage Plane projects (list, get, create, update, delete, archive, unarchive).
# Usage:   plane projects <action> [args]
# Actions: list, get, create, update, delete, archive, unarchive
#
# Unit 4 stub — full implementation lands in Unit 6.
[ "${__PLANE_RESOURCE_PROJECTS_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_PROJECTS_LOADED=1

_help_resource_projects() {
  cat <<'EOF'
plane projects — manage Plane projects

Actions:
  list                       List projects in the workspace
  get <project_id>           Get one project by UUID
  create --name <name>       Create a project
  update <project_id> ...    Update a project (fields TBD in Unit 6)
  delete <project_id>        Delete a project (destructive — requires --execute)
  archive <project_id>       Archive a project (destructive — requires --execute)
  unarchive <project_id>     Unarchive a project

Flags: see `plane --help` for global flags.
EOF
}
