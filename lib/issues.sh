#!/usr/bin/env bash
# Summary: manage Plane issues / work items (list, get, create, update, delete, search).
# Usage:   plane issues <action> [args]
# Actions: list, get, create, update, delete, search
[ "${__PLANE_RESOURCE_ISSUES_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_ISSUES_LOADED=1

_ISSUES_SUMMARY="${PLANE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}/summaries/issues.jq"

_help_resource_issues() {
  cat <<'EOF'
plane issues — manage Plane work items (a.k.a. issues)

Actions:
  list --project <id> [--limit N] [--cursor S] [--all]
                                        List issues in a project
  get --project <id> <issue_id>         Get one issue (UUID, project-scoped)
  create --project <id> --name <name> [--data @file | <json>]
                                        Create an issue
  update --project <id> <issue_id> [--name <name>] [--data ...]
                                        Update an issue
  delete --project <id> <issue_id> [--execute]
                                        Delete an issue (destructive)
  search --query <text> [--limit N]     Workspace-wide issue search

To resolve a human identifier (PROJ-123), use `plane resolve PROJ-123`.
EOF
}

_issues_require_project() { [ -n "$1" ] || _parse_die 2 "--project <id> required"; }

_issues_list() {
  local proj="" args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)  _help_resource_issues; return 0 ;;
      --project)  proj="$2"; shift 2 ;;
      --page)     _parse_die 2 "--page not supported; use --cursor or --all" ;;
      *)          args+=("$1"); shift ;;
    esac
  done
  _issues_require_project "$proj"
  _resource_paginate issues list "$_ISSUES_SUMMARY" "project_id=$proj" "${args[@]:-}"
}

_issues_get() {
  local proj="" iid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_issues; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --*)       _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$iid" ]; then iid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _issues_require_project "$proj"
  [ -n "$iid" ] || _parse_die 2 "issues get: issue_id required"
  _resource_call issues get "$_ISSUES_SUMMARY" "" "project_id=$proj" "issue_id=$iid"
}

_issues_build_body() {
  local name="" data=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name)    name="$2"; shift 2 ;;
      --data)    data="$2"; shift 2 ;;
      --execute) shift ;;
      *)         shift ;;
    esac
  done
  if [ -n "$data" ]; then
    _resource_parse_data_arg "$data"
    return 0
  fi
  [ -n "$name" ] || _parse_die 2 "issues: specify --name or --data"
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/plane-body.XXXXXX")
  chmod 0600 "$tmp" 2>/dev/null || true
  _core_register_tmp "$tmp"
  _core_jq_body name "$name" > "$tmp"
  printf '%s' "$tmp"
}

_issues_create() {
  local proj="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_issues; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      *)         flags+=("$1"); shift ;;
    esac
  done
  _issues_require_project "$proj"
  local body_file
  body_file=$(_issues_build_body "${flags[@]:-}") || return $?
  _resource_call issues create "$_ISSUES_SUMMARY" "$body_file" "project_id=$proj"
}

_issues_update() {
  local proj="" iid="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_issues; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --name|--data) flags+=("$1" "$2"); shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$iid" ]; then iid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _issues_require_project "$proj"
  [ -n "$iid" ] || _parse_die 2 "issues update: issue_id required"
  local body_file
  body_file=$(_issues_build_body "${flags[@]:-}") || return $?
  _resource_call issues update "$_ISSUES_SUMMARY" "$body_file" "project_id=$proj" "issue_id=$iid"
}

_issues_delete() {
  local proj="" iid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_issues; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$iid" ]; then iid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _issues_require_project "$proj"
  [ -n "$iid" ] || _parse_die 2 "issues delete: issue_id required"
  _resource_call issues delete "$_ISSUES_SUMMARY" "" "project_id=$proj" "issue_id=$iid"
}

_issues_search() {
  local query="" limit=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_issues; return 0 ;;
      --query)   query="$2"; shift 2 ;;
      --limit)   limit="$2"; shift 2 ;;
      --*)       _parse_die 2 "unknown flag: $1" ;;
      *)         _parse_die 2 "unexpected arg: $1" ;;
    esac
  done
  [ -n "$query" ] || _parse_die 2 "issues search: --query required"
  local extra=(--query "search=$query")
  [ -n "$limit" ] && extra+=(--limit "$limit")
  _resource_paginate issues search "$_ISSUES_SUMMARY" "${extra[@]}"
}
