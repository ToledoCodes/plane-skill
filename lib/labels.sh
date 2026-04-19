#!/usr/bin/env bash
# Summary: manage Plane project labels.
# Usage:   plane labels <action> [args]
# Actions: list, get, create, update, delete
[ "${__PLANE_RESOURCE_LABELS_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_LABELS_LOADED=1

_LABELS_SUMMARY="${PLANE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}/summaries/labels.jq"

_help_resource_labels() {
  cat <<'EOF'
plane labels — manage Plane project labels

Actions:
  list --project <id> [--limit N] [--cursor S] [--all]
  get --project <id> <label_id>
  create --project <id> --name <name> [--color <#rgb>] [--data ...]
  update --project <id> <label_id> [--name ...] [--color ...] [--data ...]
  delete --project <id> <label_id> [--execute]   (destructive)
EOF
}

_labels_require_project() { [ -n "$1" ] || _parse_die 2 "--project <id> required"; }

_labels_list() {
  local proj="" args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_labels; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --page) _parse_die 2 "--page not supported; use --cursor or --all" ;;
      *) args+=("$1"); shift ;;
    esac
  done
  _labels_require_project "$proj"
  _resource_paginate labels list "$_LABELS_SUMMARY" "project_id=$proj" "${args[@]:-}"
}

_labels_get() {
  local proj="" lid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_labels; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$lid" ]; then lid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _labels_require_project "$proj"; [ -n "$lid" ] || _parse_die 2 "labels get: label_id required"
  _resource_call labels get "$_LABELS_SUMMARY" "" "project_id=$proj" "label_id=$lid"
}

_labels_build_body() {
  local name="" color="" data=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name)    name="$2"; shift 2 ;;
      --color)   color="$2"; shift 2 ;;
      --data)    data="$2"; shift 2 ;;
      --execute) shift ;;
      *)         shift ;;
    esac
  done
  if [ -n "$data" ]; then
    _resource_parse_data_arg "$data"
    return 0
  fi
  local pairs=()
  [ -n "$name" ]  && pairs+=(name "$name")
  [ -n "$color" ] && pairs+=(color "$color")
  [ ${#pairs[@]} -eq 0 ] && _parse_die 2 "labels: specify --name (and/or --color) or --data"
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/plane-body.XXXXXX")
  chmod 0600 "$tmp" 2>/dev/null || true
  _core_register_tmp "$tmp"
  _core_jq_body "${pairs[@]}" > "$tmp"
  printf '%s' "$tmp"
}

_labels_create() {
  local proj="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_labels; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      *) flags+=("$1"); shift ;;
    esac
  done
  _labels_require_project "$proj"
  local body_file
  body_file=$(_labels_build_body "${flags[@]:-}") || return $?
  _resource_call labels create "$_LABELS_SUMMARY" "$body_file" "project_id=$proj"
}

_labels_update() {
  local proj="" lid="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_labels; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --name|--color|--data) flags+=("$1" "$2"); shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$lid" ]; then lid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _labels_require_project "$proj"; [ -n "$lid" ] || _parse_die 2 "labels update: label_id required"
  local body_file
  body_file=$(_labels_build_body "${flags[@]:-}") || return $?
  _resource_call labels update "$_LABELS_SUMMARY" "$body_file" "project_id=$proj" "label_id=$lid"
}

_labels_delete() {
  local proj="" lid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_labels; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$lid" ]; then lid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _labels_require_project "$proj"; [ -n "$lid" ] || _parse_die 2 "labels delete: label_id required"
  _resource_call labels delete "$_LABELS_SUMMARY" "" "project_id=$proj" "label_id=$lid"
}
