#!/usr/bin/env bash
# Summary: manage Plane issue comments.
# Usage:   plane comments <action> [args]
# Actions: list, get, create, update, delete
[ "${__PLANE_RESOURCE_COMMENTS_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_COMMENTS_LOADED=1

_COMMENTS_SUMMARY="${PLANE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}/summaries/comments.jq"

_help_resource_comments() {
  cat <<'EOF'
plane comments — manage comments on a Plane issue

Actions:
  list --project <id> --issue <issue_id> [--limit N] [--cursor S] [--all]
  get --project <id> --issue <issue_id> <comment_id>
  create --project <id> --issue <issue_id> --comment <text> [--data ...]
  update --project <id> --issue <issue_id> <comment_id> [--comment ...] [--data ...]
  delete --project <id> --issue <issue_id> <comment_id> [--execute]   (destructive)
EOF
}

_comments_require_project_and_issue() {
  [ -n "$1" ] || _parse_die 2 "--project <id> required"
  [ -n "$2" ] || _parse_die 2 "--issue <issue_id> required"
}

_comments_list() {
  local proj="" iid="" args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_comments; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --issue)   iid="$2"; shift 2 ;;
      --page)    _parse_die 2 "--page not supported; use --cursor or --all" ;;
      *)         args+=("$1"); shift ;;
    esac
  done
  _comments_require_project_and_issue "$proj" "$iid"
  _resource_paginate comments list "$_COMMENTS_SUMMARY" \
    "project_id=$proj" "issue_id=$iid" "${args[@]:-}"
}

_comments_get() {
  local proj="" iid="" cid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_comments; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --issue)   iid="$2"; shift 2 ;;
      --*)       _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$cid" ]; then cid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _comments_require_project_and_issue "$proj" "$iid"
  [ -n "$cid" ] || _parse_die 2 "comments get: comment_id required"
  _resource_call comments get "$_COMMENTS_SUMMARY" "" \
    "project_id=$proj" "issue_id=$iid" "comment_id=$cid"
}

_comments_build_body() {
  local comment="" data=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --comment) comment="$2"; shift 2 ;;
      --data)    data="$2"; shift 2 ;;
      --execute) shift ;;
      *)         shift ;;
    esac
  done
  if [ -n "$data" ]; then _resource_parse_data_arg "$data"; return 0; fi
  [ -n "$comment" ] || _parse_die 2 "comments: specify --comment or --data"
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/plane-body.XXXXXX")
  chmod 0600 "$tmp" 2>/dev/null || true
  _core_register_tmp "$tmp"
  _core_jq_body comment_html "$comment" comment_stripped "$comment" > "$tmp"
  printf '%s' "$tmp"
}

_comments_create() {
  local proj="" iid="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_comments; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --issue)   iid="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      *)         flags+=("$1"); shift ;;
    esac
  done
  _comments_require_project_and_issue "$proj" "$iid"
  local body_file
  body_file=$(_comments_build_body "${flags[@]:-}") || return $?
  _resource_call comments create "$_COMMENTS_SUMMARY" "$body_file" \
    "project_id=$proj" "issue_id=$iid"
}

_comments_update() {
  local proj="" iid="" cid="" flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_comments; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --issue)   iid="$2"; shift 2 ;;
      --comment|--data) flags+=("$1" "$2"); shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$cid" ]; then cid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _comments_require_project_and_issue "$proj" "$iid"
  [ -n "$cid" ] || _parse_die 2 "comments update: comment_id required"
  local body_file
  body_file=$(_comments_build_body "${flags[@]:-}") || return $?
  _resource_call comments update "$_COMMENTS_SUMMARY" "$body_file" \
    "project_id=$proj" "issue_id=$iid" "comment_id=$cid"
}

_comments_delete() {
  local proj="" iid="" cid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) _help_resource_comments; return 0 ;;
      --project) proj="$2"; shift 2 ;;
      --issue)   iid="$2"; shift 2 ;;
      --execute) export PLANE_EXECUTE=1; shift ;;
      --*) _parse_die 2 "unknown flag: $1" ;;
      *) if [ -z "$cid" ]; then cid="$1"; shift
         else _parse_die 2 "unexpected arg: $1"
         fi ;;
    esac
  done
  _comments_require_project_and_issue "$proj" "$iid"
  [ -n "$cid" ] || _parse_die 2 "comments delete: comment_id required"
  _resource_call comments delete "$_COMMENTS_SUMMARY" "" \
    "project_id=$proj" "issue_id=$iid" "comment_id=$cid"
}
