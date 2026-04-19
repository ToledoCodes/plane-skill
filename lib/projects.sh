#!/usr/bin/env bash
# Summary: manage Plane projects (list, get, create, update, delete, archive, unarchive).
# Usage:   plane projects <action> [args]
# Actions: list, get, create, update, delete, archive, unarchive
[ "${__PLANE_RESOURCE_PROJECTS_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_PROJECTS_LOADED=1

_PROJECTS_SUMMARY="${PLANE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}/summaries/projects.jq"

_help_resource_projects() {
  cat <<'EOF'
plane projects — manage Plane projects

Actions:
  list [--limit N] [--cursor S] [--all]
                           List projects in the workspace
  get <project_id>         Get one project by UUID
  create --name <name> [--identifier <abbr>] [--data @file | <json>]
                           Create a project
  update <project_id> [--name <name>] [--data @file | <json>]
                           Update a project
  delete <project_id> [--execute]
                           Delete a project (destructive — requires --execute)
  archive <project_id> [--execute]
                           Archive a project (destructive — requires --execute)
  unarchive <project_id>   Unarchive a project

Destructive verbs dry-run by default (exit 7); pass --execute to perform.
EOF
}

# Shared: absorb --execute anywhere in args so later scans ignore it.
_projects_absorb_execute() {
  local a
  for a in "$@"; do [ "$a" = "--execute" ] && export PLANE_EXECUTE=1; done
}

_projects_list() {
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_projects; return 0 ;;
      --page)    _parse_die 2 "--page not supported; use --cursor or --all" ;;
      *)         args+=("$1"); shift ;;
    esac
  done
  _resource_paginate projects list "$_PROJECTS_SUMMARY" "${args[@]:-}"
}

_projects_get() {
  local pid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_projects; return 0 ;;
      --*)       _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$pid" ]; then pid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  [ -n "$pid" ] || _parse_die 2 "projects get: project_id required"
  _resource_call projects get "$_PROJECTS_SUMMARY" "" "project_id=$pid"
}

# Build a body file from --name / --identifier / --data. Echoes the tmp path.
# --data wins; otherwise flag values compose via _core_jq_body.
_projects_build_body() {
  local name="" identifier="" data=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name)       name="$2"; shift 2 ;;
      --identifier) identifier="$2"; shift 2 ;;
      --data)       data="$2"; shift 2 ;;
      --execute)    shift ;;  # absorbed by caller
      *)            shift ;;
    esac
  done
  if [ -n "$data" ]; then
    _resource_parse_data_arg "$data"
    return 0
  fi
  local pairs=()
  [ -n "$name" ]       && pairs+=(name "$name")
  [ -n "$identifier" ] && pairs+=(identifier "$identifier")
  [ ${#pairs[@]} -eq 0 ] && _parse_die 2 "projects: specify --name (and/or --identifier) or --data"
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/plane-body.XXXXXX")
  chmod 0600 "$tmp" 2>/dev/null || true
  _core_register_tmp "$tmp"
  _core_jq_body "${pairs[@]}" > "$tmp"
  printf '%s' "$tmp"
}

_projects_create() {
  case "${1:-}" in --help|-h) _help_resource_projects; return 0 ;; esac
  _projects_absorb_execute "$@"
  local body_file
  body_file=$(_projects_build_body "$@") || return $?
  _resource_call projects create "$_PROJECTS_SUMMARY" "$body_file"
}

_projects_update() {
  local pid=""
  local flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_projects; return 0 ;;
      --name|--identifier|--data) flags+=("$1" "$2"); shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$pid" ]; then pid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  [ -n "$pid" ] || _parse_die 2 "projects update: project_id required"
  local body_file
  body_file=$(_projects_build_body "${flags[@]:-}") || return $?
  _resource_call projects update "$_PROJECTS_SUMMARY" "$body_file" "project_id=$pid"
}

_projects_delete() {
  local pid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_projects; return 0 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$pid" ]; then pid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  [ -n "$pid" ] || _parse_die 2 "projects delete: project_id required"
  _resource_call projects delete "$_PROJECTS_SUMMARY" "" "project_id=$pid"
}

_projects_archive() {
  local pid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_projects; return 0 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$pid" ]; then pid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  [ -n "$pid" ] || _parse_die 2 "projects archive: project_id required"
  _resource_call projects archive "$_PROJECTS_SUMMARY" "" "project_id=$pid"
}

_projects_unarchive() {
  local pid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_projects; return 0 ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$pid" ]; then pid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  [ -n "$pid" ] || _parse_die 2 "projects unarchive: project_id required"
  _resource_call projects unarchive "$_PROJECTS_SUMMARY" "" "project_id=$pid"
}
