#!/usr/bin/env bash
# Summary: manage Plane project time-entries (timer start/stop lives in plane-time-tracking).
# Usage:   plane time-entries <action> [args]
# Actions: list, get, create, update, delete, list-workspace
[ "${__PLANE_RESOURCE_TIME_ENTRIES_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_TIME_ENTRIES_LOADED=1

_TIME_ENTRIES_SUMMARY="${PLANE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}/summaries/time-entries.jq"

_help_resource_time_entries() {
  cat <<'EOF'
plane time-entries — manage Plane project time entries

Actions:
  list --project <id> [--limit N] [--cursor S] [--all]
  get --project <id> <time_entry_id>
  create --project <id> --issue <issue_id> --start <iso> --duration <sec> [--data ...]
  update --project <id> <time_entry_id> [--duration ...] [--data ...]
  delete --project <id> <time_entry_id> [--execute]   (destructive)
  list-workspace [--limit N] [--cursor S] [--all]

The plane-time-tracking skill layers timer semantics on top of these records.
EOF
}

_time_entries_require_project() { [ -n "$1" ] || _parse_die 2 "--project <id> required"; }

_time_entries_list() {
  local proj="" args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_time_entries; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --page) _parse_die 2 "--page not supported; use --cursor or --all" ;;
      *) args+=("$1"); shift ;;
    esac
  done
  _time_entries_require_project "$proj"
  _resource_paginate time-entries list "$_TIME_ENTRIES_SUMMARY" \
    "project_id=$proj" "${args[@]:-}"
}

_time_entries_list_workspace() {
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_time_entries; return 0 ;;
      --page) _parse_die 2 "--page not supported; use --cursor or --all" ;;
      *) args+=("$1"); shift ;;
    esac
  done
  _resource_paginate time-entries list-workspace "$_TIME_ENTRIES_SUMMARY" "${args[@]:-}"
}

_time_entries_get() {
  local proj="" teid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_time_entries; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$teid" ]; then teid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _time_entries_require_project "$proj"; [ -n "$teid" ] || _parse_die 2 "time-entries get: id required"
  _resource_call time-entries get "$_TIME_ENTRIES_SUMMARY" "" \
    "project_id=$proj" "time_entry_id=$teid"
}

_time_entries_build_body() {
  local issue="" start="" duration="" description="" data=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --issue)       issue="$2"; shift 2 ;;
      --start)       start="$2"; shift 2 ;;
      --duration)    duration="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --data)        data="$2"; shift 2 ;;
      --execute)     shift ;;
      *)             shift ;;
    esac
  done
  if [ -n "$data" ]; then _resource_parse_data_arg "$data"; return 0; fi
  local pairs=()
  [ -n "$issue" ]       && pairs+=(issue "$issue")
  [ -n "$start" ]       && pairs+=(start_time "$start")
  [ -n "$duration" ]    && pairs+=(duration "$duration")
  [ -n "$description" ] && pairs+=(description "$description")
  [ ${#pairs[@]} -eq 0 ] && _parse_die 2 "time-entries: specify body fields (--issue --start --duration) or --data"
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/plane-body.XXXXXX")
  chmod 0600 "$tmp" 2>/dev/null || true
  _core_register_tmp "$tmp"
  _core_jq_body "${pairs[@]}" > "$tmp"
  printf '%s' "$tmp"
}

_time_entries_create() {
  local proj="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_time_entries; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      *) flags+=("$1"); shift ;;
    esac
  done
  _time_entries_require_project "$proj"
  local body_file
  body_file=$(_time_entries_build_body "${flags[@]:-}") || return $?
  _resource_call time-entries create "$_TIME_ENTRIES_SUMMARY" "$body_file" "project_id=$proj"
}

_time_entries_update() {
  local proj="" teid="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_time_entries; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --issue|--start|--duration|--description|--data) flags+=("$1" "$2"); shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$teid" ]; then teid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _time_entries_require_project "$proj"; [ -n "$teid" ] || _parse_die 2 "time-entries update: id required"
  local body_file
  body_file=$(_time_entries_build_body "${flags[@]:-}") || return $?
  _resource_call time-entries update "$_TIME_ENTRIES_SUMMARY" "$body_file" \
    "project_id=$proj" "time_entry_id=$teid"
}

_time_entries_delete() {
  local proj="" teid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_time_entries; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$teid" ]; then teid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _time_entries_require_project "$proj"; [ -n "$teid" ] || _parse_die 2 "time-entries delete: id required"
  _resource_call time-entries delete "$_TIME_ENTRIES_SUMMARY" "" \
    "project_id=$proj" "time_entry_id=$teid"
}
