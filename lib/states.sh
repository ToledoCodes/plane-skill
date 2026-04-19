#!/usr/bin/env bash
# Summary: manage Plane project workflow states.
# Usage:   plane states <action> [args]
# Actions: list, get, create, update, delete
[ "${__PLANE_RESOURCE_STATES_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_STATES_LOADED=1

_STATES_SUMMARY="${PLANE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}/summaries/states.jq"

_help_resource_states() {
  cat <<'EOF'
plane states — manage Plane workflow states per project

Actions:
  list --project <id> [--limit N] [--cursor S] [--all]
  get --project <id> <state_id>
  create --project <id> --name <name> [--group <backlog|unstarted|started|completed|cancelled>] [--data ...]
  update --project <id> <state_id> [--name ...] [--group ...] [--data ...]
  delete --project <id> <state_id> [--execute]   (destructive)
EOF
}

_states_require_project() { [ -n "$1" ] || _parse_die 2 "--project <id> required"; }

_states_list() {
  local proj="" args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_states; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --page) _parse_die 2 "--page not supported; use --cursor or --all" ;;
      *) args+=("$1"); shift ;;
    esac
  done
  _states_require_project "$proj"
  _resource_paginate states list "$_STATES_SUMMARY" "project_id=$proj" "${args[@]:-}"
}

_states_get() {
  local proj="" sid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_states; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$sid" ]; then sid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _states_require_project "$proj"; [ -n "$sid" ] || _parse_die 2 "states get: state_id required"
  _resource_call states get "$_STATES_SUMMARY" "" "project_id=$proj" "state_id=$sid"
}

_states_build_body() {
  local name="" group="" data=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --group) group="$2"; shift 2 ;;
      --data) data="$2"; shift 2 ;;
      --execute) shift ;;
      *) shift ;;
    esac
  done
  if [ -n "$data" ]; then _resource_parse_data_arg "$data"; return 0; fi
  local pairs=()
  [ -n "$name" ]  && pairs+=(name "$name")
  [ -n "$group" ] && pairs+=(group "$group")
  [ ${#pairs[@]} -eq 0 ] && _parse_die 2 "states: specify --name (and/or --group) or --data"
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/plane-body.XXXXXX")
  chmod 0600 "$tmp" 2>/dev/null || true
  _core_register_tmp "$tmp"
  _core_jq_body "${pairs[@]}" > "$tmp"
  printf '%s' "$tmp"
}

_states_create() {
  local proj="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_states; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      *) flags+=("$1"); shift ;;
    esac
  done
  _states_require_project "$proj"
  local body_file
  body_file=$(_states_build_body "${flags[@]:-}") || return $?
  _resource_call states create "$_STATES_SUMMARY" "$body_file" "project_id=$proj"
}

_states_update() {
  local proj="" sid="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_states; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --name|--group|--data) flags+=("$1" "$2"); shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$sid" ]; then sid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _states_require_project "$proj"; [ -n "$sid" ] || _parse_die 2 "states update: state_id required"
  local body_file
  body_file=$(_states_build_body "${flags[@]:-}") || return $?
  _resource_call states update "$_STATES_SUMMARY" "$body_file" "project_id=$proj" "state_id=$sid"
}

_states_delete() {
  local proj="" sid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_states; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$sid" ]; then sid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _states_require_project "$proj"; [ -n "$sid" ] || _parse_die 2 "states delete: state_id required"
  _resource_call states delete "$_STATES_SUMMARY" "" "project_id=$proj" "state_id=$sid"
}
