#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
#   SC2016: '${var}' placeholders are intentionally literal templates.
#   SC2034: PLANE_ENDPOINTS is consumed by bin/plane and resource libs.
# Summary: hand-authored resource.action -> "METHOD path" table for T1 resources.
# Usage: sourced by bin/plane once; resource libs look up their endpoints here.
#
# Authoritative source: docs/plane-openapi-<timestamp>.yaml. Authored from the
# plan.toledo.codes capture on 2026-04-19. When Plane adds or changes a T1
# endpoint, re-capture the spec and update this file — do not generate.
#
# Path conventions used here:
#   /projects/... and other project-scoped paths are prefixed at call time
#     with /api/v1/workspaces/<slug>/ by _core_build_url.
#   /issues/<identifier>/ is workspace-scoped identifier resolution; same prefix.
#   Bare path substrings use ${var} placeholders the resource libs fill in.
#
# Notes:
#   - Plane exposes /issues/ and /work-items/ as aliases under project scope.
#     We standardise on /issues/ for CLI consistency with the prior skill.
#   - POST /projects/<id>/archive/ archives; DELETE on the same URL unarchives.
#   - Plane has no bulk-create / bulk-delete time-entry endpoints in v1 of the
#     public API. Deferred from Unit 6 per Unit 3 findings; callers use repeated
#     single calls or `plane api` in a loop.
[ "${__PLANE_ENDPOINT_MAP_LOADED:-0}" = "1" ] && return 0
__PLANE_ENDPOINT_MAP_LOADED=1

if [ -z "${BASH_VERSINFO+x}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'plane: _endpoint_map.sh requires bash >= 4 (assoc arrays).\n' >&2
  exit 3
fi

# The ${var} placeholders below are intentionally kept literal — resource libs
# expand them at call time via eval or envsubst once they know the IDs.
# shellcheck disable=SC2034  # Consumed by bin/plane and resource libs.
declare -gA PLANE_ENDPOINTS

# ===== projects =====
PLANE_ENDPOINTS[projects.list]='GET /projects/'
PLANE_ENDPOINTS[projects.get]='GET /projects/${project_id}/'
PLANE_ENDPOINTS[projects.create]='POST /projects/'
PLANE_ENDPOINTS[projects.update]='PATCH /projects/${project_id}/'
PLANE_ENDPOINTS[projects.delete]='DELETE /projects/${project_id}/'
PLANE_ENDPOINTS[projects.archive]='POST /projects/${project_id}/archive/'
PLANE_ENDPOINTS[projects.unarchive]='DELETE /projects/${project_id}/archive/'

# ===== issues =====
PLANE_ENDPOINTS[issues.list]='GET /projects/${project_id}/issues/'
PLANE_ENDPOINTS[issues.get]='GET /projects/${project_id}/issues/${issue_id}/'
PLANE_ENDPOINTS[issues.create]='POST /projects/${project_id}/issues/'
PLANE_ENDPOINTS[issues.update]='PATCH /projects/${project_id}/issues/${issue_id}/'
PLANE_ENDPOINTS[issues.delete]='DELETE /projects/${project_id}/issues/${issue_id}/'
# Identifier resolution lives at workspace scope; no project in path.
PLANE_ENDPOINTS[issues.resolve]='GET /issues/${identifier}/'
PLANE_ENDPOINTS[issues.search]='GET /issues/search/'

# ===== cycles =====
PLANE_ENDPOINTS[cycles.list]='GET /projects/${project_id}/cycles/'
PLANE_ENDPOINTS[cycles.get]='GET /projects/${project_id}/cycles/${cycle_id}/'
PLANE_ENDPOINTS[cycles.create]='POST /projects/${project_id}/cycles/'
PLANE_ENDPOINTS[cycles.update]='PATCH /projects/${project_id}/cycles/${cycle_id}/'
PLANE_ENDPOINTS[cycles.delete]='DELETE /projects/${project_id}/cycles/${cycle_id}/'
PLANE_ENDPOINTS[cycles.archive]='POST /projects/${project_id}/cycles/${cycle_id}/archive/'
PLANE_ENDPOINTS[cycles.list-work-items]='GET /projects/${project_id}/cycles/${cycle_id}/cycle-issues/'
PLANE_ENDPOINTS[cycles.add-work-items]='POST /projects/${project_id}/cycles/${cycle_id}/cycle-issues/'
PLANE_ENDPOINTS[cycles.remove-work-item]='DELETE /projects/${project_id}/cycles/${cycle_id}/cycle-issues/${issue_id}/'
PLANE_ENDPOINTS[cycles.transfer-work-items]='POST /projects/${project_id}/cycles/${cycle_id}/transfer-issues/'

# ===== labels =====
PLANE_ENDPOINTS[labels.list]='GET /projects/${project_id}/labels/'
PLANE_ENDPOINTS[labels.get]='GET /projects/${project_id}/labels/${label_id}/'
PLANE_ENDPOINTS[labels.create]='POST /projects/${project_id}/labels/'
PLANE_ENDPOINTS[labels.update]='PATCH /projects/${project_id}/labels/${label_id}/'
PLANE_ENDPOINTS[labels.delete]='DELETE /projects/${project_id}/labels/${label_id}/'

# ===== states =====
PLANE_ENDPOINTS[states.list]='GET /projects/${project_id}/states/'
PLANE_ENDPOINTS[states.get]='GET /projects/${project_id}/states/${state_id}/'
PLANE_ENDPOINTS[states.create]='POST /projects/${project_id}/states/'
PLANE_ENDPOINTS[states.update]='PATCH /projects/${project_id}/states/${state_id}/'
PLANE_ENDPOINTS[states.delete]='DELETE /projects/${project_id}/states/${state_id}/'

# ===== comments (issue-scoped) =====
PLANE_ENDPOINTS[comments.list]='GET /projects/${project_id}/issues/${issue_id}/comments/'
PLANE_ENDPOINTS[comments.get]='GET /projects/${project_id}/issues/${issue_id}/comments/${comment_id}/'
PLANE_ENDPOINTS[comments.create]='POST /projects/${project_id}/issues/${issue_id}/comments/'
PLANE_ENDPOINTS[comments.update]='PATCH /projects/${project_id}/issues/${issue_id}/comments/${comment_id}/'
PLANE_ENDPOINTS[comments.delete]='DELETE /projects/${project_id}/issues/${issue_id}/comments/${comment_id}/'

# ===== time-entries =====
PLANE_ENDPOINTS[time-entries.list]='GET /projects/${project_id}/time-entries/'
PLANE_ENDPOINTS[time-entries.get]='GET /projects/${project_id}/time-entries/${time_entry_id}/'
PLANE_ENDPOINTS[time-entries.create]='POST /projects/${project_id}/time-entries/'
PLANE_ENDPOINTS[time-entries.update]='PATCH /projects/${project_id}/time-entries/${time_entry_id}/'
PLANE_ENDPOINTS[time-entries.delete]='DELETE /projects/${project_id}/time-entries/${time_entry_id}/'
# Workspace-wide listing across all projects.
PLANE_ENDPOINTS[time-entries.list-workspace]='GET /time-entries/'
