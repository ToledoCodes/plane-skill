#!/usr/bin/env bash
# Summary: manage Plane issue comments.
# Usage:   plane comments <action> [args]
# Actions: list, get, create, update, delete
#
# Unit 4 stub — full implementation lands in Unit 6.
[ "${__PLANE_RESOURCE_COMMENTS_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_COMMENTS_LOADED=1

_help_resource_comments() {
  cat <<'EOF'
plane comments — manage comments on a Plane issue

Actions:
  list --project <id> --issue <issue_id>                 List comments on an issue
  get --project <id> --issue <issue_id> <comment_id>     Get one comment
  create --project <id> --issue <issue_id> --comment <text>
                                                         Create a comment
  update --project <id> --issue <issue_id> <comment_id>  Update a comment
  delete --project <id> --issue <issue_id> <comment_id>  Delete a comment (destructive)
EOF
}
