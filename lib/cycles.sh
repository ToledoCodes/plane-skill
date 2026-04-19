#!/usr/bin/env bash
# Summary: manage Plane cycles and their work-item membership.
# Usage:   plane cycles <action> [args]
# Actions: list, get, create, update, delete, archive,
#          list-work-items, add-work-items, remove-work-item, transfer-work-items
[ "${__PLANE_RESOURCE_CYCLES_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_CYCLES_LOADED=1

_CYCLES_SUMMARY="${PLANE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}/summaries/cycles.jq"
_CYCLES_ISSUE_SUMMARY="${PLANE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}/summaries/issues.jq"

_help_resource_cycles() {
  cat <<'EOF'
plane cycles — manage Plane cycles

Core CRUD:
  list --project <id> [--limit N] [--cursor S] [--all]
  get --project <id> <cycle_id>
  create --project <id> --name <name> [--start-date <iso>] [--end-date <iso>] [--data ...]
  update --project <id> <cycle_id> [--name ...] [--start-date ...] [--end-date ...] [--data ...]
  delete --project <id> <cycle_id> [--execute]                 (destructive)
  archive --project <id> <cycle_id> [--execute]                (destructive)

Work-item membership:
  list-work-items --project <id> <cycle_id> [--limit N] [--cursor S] [--all]
  add-work-items --project <id> <cycle_id> --issues <id1,id2,...>
  remove-work-item --project <id> <cycle_id> <issue_id> [--execute]   (destructive)
  transfer-work-items --project <id> <cycle_id> --target <cycle_id> [--execute]
                                                               (destructive)
EOF
}

_cycles_require_project() { [ -n "$1" ] || _parse_die 2 "--project <id> required"; }

_cycles_list() {
  local proj="" args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_cycles; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --page) _parse_die 2 "--page not supported; use --cursor or --all" ;;
      *) args+=("$1"); shift ;;
    esac
  done
  _cycles_require_project "$proj"
  _resource_paginate cycles list "$_CYCLES_SUMMARY" "project_id=$proj" "${args[@]:-}"
}

_cycles_get() {
  local proj="" cid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_cycles; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$cid" ]; then cid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _cycles_require_project "$proj"; [ -n "$cid" ] || _parse_die 2 "cycles get: cycle_id required"
  _resource_call cycles get "$_CYCLES_SUMMARY" "" "project_id=$proj" "cycle_id=$cid"
}

_cycles_build_body() {
  local name="" start_date="" end_date="" description="" data=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name)        name="$2"; shift 2 ;;
      --start-date)  start_date="$2"; shift 2 ;;
      --end-date)    end_date="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --data)        data="$2"; shift 2 ;;
      --execute)     shift ;;
      *)             shift ;;
    esac
  done
  if [ -n "$data" ]; then _resource_parse_data_arg "$data"; return 0; fi
  local pairs=()
  [ -n "$name" ]        && pairs+=(name "$name")
  [ -n "$start_date" ]  && pairs+=(start_date "$start_date")
  [ -n "$end_date" ]    && pairs+=(end_date "$end_date")
  [ -n "$description" ] && pairs+=(description "$description")
  [ ${#pairs[@]} -eq 0 ] && _parse_die 2 "cycles: specify --name (and optional dates) or --data"
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/plane-body.XXXXXX")
  chmod 0600 "$tmp" 2>/dev/null || true
  _core_register_tmp "$tmp"
  _core_jq_body "${pairs[@]}" > "$tmp"
  printf '%s' "$tmp"
}

_cycles_create() {
  local proj="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_cycles; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      *) flags+=("$1"); shift ;;
    esac
  done
  _cycles_require_project "$proj"
  local body_file
  body_file=$(_cycles_build_body "${flags[@]:-}") || return $?
  _resource_call cycles create "$_CYCLES_SUMMARY" "$body_file" "project_id=$proj"
}

_cycles_update() {
  local proj="" cid="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_cycles; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --name|--start-date|--end-date|--description|--data) flags+=("$1" "$2"); shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$cid" ]; then cid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _cycles_require_project "$proj"; [ -n "$cid" ] || _parse_die 2 "cycles update: cycle_id required"
  local body_file
  body_file=$(_cycles_build_body "${flags[@]:-}") || return $?
  _resource_call cycles update "$_CYCLES_SUMMARY" "$body_file" "project_id=$proj" "cycle_id=$cid"
}

_cycles_delete() {
  local proj="" cid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_cycles; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$cid" ]; then cid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _cycles_require_project "$proj"; [ -n "$cid" ] || _parse_die 2 "cycles delete: cycle_id required"
  _resource_call cycles delete "$_CYCLES_SUMMARY" "" "project_id=$proj" "cycle_id=$cid"
}

_cycles_archive() {
  local proj="" cid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_cycles; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$cid" ]; then cid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _cycles_require_project "$proj"; [ -n "$cid" ] || _parse_die 2 "cycles archive: cycle_id required"
  _resource_call cycles archive "$_CYCLES_SUMMARY" "" "project_id=$proj" "cycle_id=$cid"
}

_cycles_list_work_items() {
  local proj="" cid="" args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_cycles; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --page) _parse_die 2 "--page not supported; use --cursor or --all" ;;
      --*) args+=("$1"); shift ;;
      *) if [ -z "$cid" ]; then cid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _cycles_require_project "$proj"; [ -n "$cid" ] || _parse_die 2 "cycles list-work-items: cycle_id required"
  _resource_paginate cycles list-work-items "$_CYCLES_ISSUE_SUMMARY" \
    "project_id=$proj" "cycle_id=$cid" "${args[@]:-}"
}

_cycles_add_work_items() {
  local proj="" cid="" issues="" data=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_cycles; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --issues)  issues="$2"; shift 2 ;;
      --data)    data="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$cid" ]; then cid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _cycles_require_project "$proj"
  [ -n "$cid" ] || _parse_die 2 "cycles add-work-items: cycle_id required"
  local body_file
  if [ -n "$data" ]; then
    body_file=$(_resource_parse_data_arg "$data")
  else
    [ -n "$issues" ] || _parse_die 2 "cycles add-work-items: --issues <id1,id2,...> or --data required"
    body_file=$(mktemp "${TMPDIR:-/tmp}/plane-body.XXXXXX")
    chmod 0600 "$body_file" 2>/dev/null || true
    _core_register_tmp "$body_file"
    jq -n --arg ids "$issues" '{issues: ($ids | split(","))}' > "$body_file"
  fi
  _resource_call cycles add-work-items "$_CYCLES_ISSUE_SUMMARY" "$body_file" \
    "project_id=$proj" "cycle_id=$cid"
}

_cycles_remove_work_item() {
  local proj="" cid="" iid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_cycles; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *)
        if [ -z "$cid" ]; then cid="$1"
        elif [ -z "$iid" ]; then iid="$1"
        else _parse_die 2 "unexpected arg: $1"
        fi
        shift
        ;;
    esac
  done
  _cycles_require_project "$proj"
  [ -n "$cid" ] || _parse_die 2 "cycles remove-work-item: cycle_id required"
  [ -n "$iid" ] || _parse_die 2 "cycles remove-work-item: issue_id required"
  _resource_call cycles remove-work-item "$_CYCLES_ISSUE_SUMMARY" "" \
    "project_id=$proj" "cycle_id=$cid" "issue_id=$iid"
}

_cycles_transfer_work_items() {
  local proj="" cid="" target="" data=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_cycles; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --target)  target="$2"; shift 2 ;;
      --data)    data="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$cid" ]; then cid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _cycles_require_project "$proj"
  [ -n "$cid" ] || _parse_die 2 "cycles transfer-work-items: cycle_id required"
  local body_file
  if [ -n "$data" ]; then
    body_file=$(_resource_parse_data_arg "$data")
  else
    [ -n "$target" ] || _parse_die 2 "cycles transfer-work-items: --target <cycle_id> or --data required"
    body_file=$(mktemp "${TMPDIR:-/tmp}/plane-body.XXXXXX")
    chmod 0600 "$body_file" 2>/dev/null || true
    _core_register_tmp "$body_file"
    _core_jq_body new_cycle_id "$target" > "$body_file"
  fi
  _resource_call cycles transfer-work-items "$_CYCLES_SUMMARY" "$body_file" \
    "project_id=$proj" "cycle_id=$cid"
}
