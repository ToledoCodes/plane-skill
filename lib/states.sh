#!/usr/bin/env bash
# Summary: manage Plane project workflow states.
# Usage:   plane states <action> [args]
# Actions: list, get, create, update, delete
#
# Unit 4 stub — full implementation lands in Unit 6.
[ "${__PLANE_RESOURCE_STATES_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_STATES_LOADED=1

_help_resource_states() {
  cat <<'EOF'
plane states — manage Plane workflow states per project

Actions:
  list --project <id>                       List states in a project
  get --project <id> <state_id>             Get one state
  create --project <id> --name <name>       Create a state
  update --project <id> <state_id>          Update a state
  delete --project <id> <state_id>          Delete a state (destructive)
EOF
}
