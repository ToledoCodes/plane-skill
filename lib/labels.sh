#!/usr/bin/env bash
# Summary: manage Plane project labels.
# Usage:   plane labels <action> [args]
# Actions: list, get, create, update, delete
#
# Unit 4 stub — full implementation lands in Unit 6.
[ "${__PLANE_RESOURCE_LABELS_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_LABELS_LOADED=1

_help_resource_labels() {
  cat <<'EOF'
plane labels — manage Plane project labels

Actions:
  list --project <id>                       List labels in a project
  get --project <id> <label_id>             Get one label
  create --project <id> --name <name>       Create a label
  update --project <id> <label_id>          Update a label
  delete --project <id> <label_id>          Delete a label (destructive)
EOF
}
