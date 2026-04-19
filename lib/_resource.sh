#!/usr/bin/env bash
# Summary: shared resource-action machinery (endpoint lookup, interpolation,
#          destructive-verb classification, dry-run transcripts, output
#          routing, pagination loop).
# Usage:   sourced by every resource lib via bin/plane; never executed directly.
#
# Each T1 resource lib implements `<resource>_<action>` functions that parse
# the action's flags and then call one of:
#
#   _resource_paginate  <resource> <action> <summary> [var=val ...]
#                       [--limit N] [--cursor S] [--all]
#   _resource_call      <resource> <action> <summary> <body_file_or_empty>
#                       [var=val ...] [--query k=v ...]
#
# Both helpers:
#   - look up the endpoint from PLANE_ENDPOINTS[resource.action],
#   - substitute ${var} placeholders with the caller's key=value pairs,
#   - perform destructive-verb gating: if the action is destructive and
#     PLANE_EXECUTE is not 1, emit a dry-run transcript and return 7,
#   - on execute, call _core_http and pipe the body through the summary
#     jq filter (TTY) or emit raw JSON (pipe / PLANE_FORCE_JSON=1).
[ "${__PLANE_RESOURCE_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOURCE_LOADED=1

# ---- classification -------------------------------------------------------

# _resource_is_destructive <resource> <action>
# Returns 0 (destructive) or 1 (safe to execute by default).
# This is the source of truth for the dry-run gate; docs/destructive-actions.md
# must agree with the enumeration below.
_resource_is_destructive() {
  case "$1.$2" in
    projects.delete|projects.archive) return 0 ;;
    issues.delete) return 0 ;;
    cycles.delete|cycles.archive|cycles.remove-work-item|cycles.transfer-work-items) return 0 ;;
    labels.delete) return 0 ;;
    states.delete) return 0 ;;
    comments.delete) return 0 ;;
    time-entries.delete) return 0 ;;
    *) return 1 ;;
  esac
}

# ---- endpoint lookup + interpolation --------------------------------------

_resource_endpoint() {
  local key="$1"
  local val="${PLANE_ENDPOINTS[$key]:-}"
  [ -n "$val" ] || _die 3 "no endpoint registered for key: $key"
  printf '%s' "$val"
}

# _resource_expand <path_template> [key=value ...]
# Substitute ${key} with value, once per pair. Literal '$' without '{' is left alone.
_resource_expand() {
  local s="$1"; shift
  while [ $# -ge 1 ]; do
    local kv="$1"; shift
    case "$kv" in
      *=*) : ;;
      *) continue ;;
    esac
    local k="${kv%%=*}" v="${kv#*=}"
    s="${s//\$\{$k\}/$v}"
  done
  printf '%s' "$s"
}

# ---- dry-run transcript ---------------------------------------------------

# _resource_dryrun <method> <url> [<body_file>]
# Emits a human-readable transcript to stderr, then returns 7.
_resource_dryrun() {
  local method="$1" url="$2" body_file="${3:-}"
  printf 'dry-run: %s %s\n' "$method" "$url" >&2
  if [ -n "$body_file" ] && [ -f "$body_file" ]; then
    printf '  body (sensitive fields redacted):\n' >&2
    _core_redact "$body_file" | sed 's/^/    /' >&2
    printf '\n' >&2
  fi
  printf 'plane: destructive verb — re-run with --execute to perform.\n' >&2
  return 7
}

# ---- output routing -------------------------------------------------------

# Decide pretty vs JSON mode once per call.
_resource_want_json() {
  if [ "${PLANE_FORCE_JSON:-0}" = "1" ]; then return 0; fi
  if [ "${PLANE_FORCE_PRETTY:-0}" = "1" ]; then return 1; fi
  if [ -t 1 ]; then return 1; fi
  return 0
}

# _resource_output <body_file> [<summary_jq>]
# Pretty mode applies the summary filter per item (envelope → per-result) or
# once (single object). Falls back to `jq .` when no summary is provided.
# JSON mode cats the body verbatim.
_resource_output() {
  local body="$1" summary="${2:-}"
  if _resource_want_json; then
    cat "$body"
    # Guarantee trailing newline so piped output doesn't glue to the prompt.
    if [ -s "$body" ]; then
      local last
      last=$(tail -c 1 "$body" 2>/dev/null)
      [ "$last" = $'\n' ] || printf '\n'
    fi
    return 0
  fi
  if [ -n "$summary" ] && [ -f "$summary" ]; then
    # If the body is a paginated envelope, run the filter per `.results[]`
    # item so the summary files can stay item-oriented.
    if jq -e 'type == "object" and has("results")' "$body" >/dev/null 2>&1; then
      local count
      count=$(jq -r '.results | length' "$body" 2>/dev/null)
      if [ "$count" = "0" ]; then
        printf '# no results\n'
        return 0
      fi
      jq -c '.results[]' "$body" | while IFS= read -r item; do
        printf '%s' "$item" | jq -rf "$summary" 2>/dev/null
      done
      return 0
    fi
    jq -rf "$summary" "$body" 2>/dev/null || cat "$body"
  else
    jq . "$body" 2>/dev/null || cat "$body"
  fi
}

# ---- single-shot call (GET/POST/PATCH/DELETE, no pagination) --------------

# _resource_call <resource> <action> <summary_or_empty> <body_file_or_empty>
#                [var=val ...] [--query k=v ...] [--execute]
# Returns 0 on success; propagates _core_http exits on errors.
_resource_call() {
  local resource="$1" action="$2" summary="$3" body_file="$4"
  shift 4

  local interpolate_args=()
  local query_args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --query)    query_args+=(--query "$2"); shift 2 ;;
      --execute)  export PLANE_EXECUTE=1; shift ;;
      *=*)        interpolate_args+=("$1"); shift ;;
      *)          shift ;;
    esac
  done

  local endpoint_value method endpoint_path final_path
  endpoint_value=$(_resource_endpoint "$resource.$action")
  method="${endpoint_value%% *}"
  endpoint_path="${endpoint_value#* }"
  final_path=$(_resource_expand "$endpoint_path" "${interpolate_args[@]}")

  _core_preflight
  _core_config_resolve

  if _resource_is_destructive "$resource" "$action" \
     && [ "${PLANE_EXECUTE:-0}" != "1" ]; then
    local display_url
    display_url=$(_core_build_url "$final_path")
    _resource_dryrun "$method" "$display_url" "$body_file"
    return 7
  fi

  local http_args=("$method" "$final_path")
  [ -n "$body_file" ] && http_args+=(--body "$body_file")
  if [ ${#query_args[@]} -gt 0 ]; then
    http_args+=("${query_args[@]}")
  fi

  local out body
  out=$(_core_http "${http_args[@]}") || return $?
  body="${out#*$'\t'}"

  # 204 No Content has no body; just return.
  if [ ! -s "$body" ]; then
    return 0
  fi

  _resource_output "$body" "$summary"
}

# ---- pagination loop (GET list) ------------------------------------------

# _resource_paginate <resource> <action> <summary> [--limit N] [--cursor S]
#                    [--all] [var=val ...] [--query k=v ...]
_resource_paginate() {
  local resource="$1" action="$2" summary="$3"
  shift 3

  local limit="" cursor="" all=0
  local interpolate_args=()
  local query_args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit)   limit=$(_parse_clamp_limit "$2"); shift 2 ;;
      --cursor)  cursor="$2"; shift 2 ;;
      --all)     all=1; shift ;;
      --query)   query_args+=(--query "$2"); shift 2 ;;
      *=*)       interpolate_args+=("$1"); shift ;;
      *)         shift ;;
    esac
  done

  local endpoint_value method endpoint_path final_path
  endpoint_value=$(_resource_endpoint "$resource.$action")
  method="${endpoint_value%% *}"
  endpoint_path="${endpoint_value#* }"
  final_path=$(_resource_expand "$endpoint_path" "${interpolate_args[@]}")

  _core_preflight
  _core_config_resolve

  # Non-paginated: single call.
  if [ "$all" != "1" ]; then
    local q=()
    [ -n "$limit" ]  && q+=(--query "per_page=$limit")
    [ -n "$cursor" ] && q+=(--query "cursor=$cursor")
    [ ${#query_args[@]} -gt 0 ] && q+=("${query_args[@]}")
    local out body
    out=$(_core_http "$method" "$final_path" "${q[@]}") || return $?
    body="${out#*$'\t'}"
    _resource_output "$body" "$summary"
    return 0
  fi

  # --all: loop until next_cursor absent or cap hit.
  local items_emitted=0 cap=500
  local want_json=1
  _resource_want_json || want_json=0

  while :; do
    local q=()
    [ -n "$limit" ]  && q+=(--query "per_page=$limit")
    [ -n "$cursor" ] && q+=(--query "cursor=$cursor")
    [ ${#query_args[@]} -gt 0 ] && q+=("${query_args[@]}")

    local out body
    out=$(_core_http "$method" "$final_path" "${q[@]}") || return $?
    body="${out#*$'\t'}"

    local item_count
    item_count=$(jq 'if type == "object" and has("results") then (.results | length) else -1 end' "$body" 2>/dev/null)
    if [ "$item_count" = "-1" ] || [ -z "$item_count" ]; then
      _resource_output "$body" "$summary"
      return 0
    fi

    items_emitted=$((items_emitted + item_count))

    if [ "$want_json" = "1" ] || [ -z "$summary" ] || [ ! -f "$summary" ]; then
      # NDJSON of results so agents can pipe or aggregate.
      jq -c '.results[]' "$body" 2>/dev/null
    else
      jq -c '.results[]' "$body" 2>/dev/null | while IFS= read -r item; do
        printf '%s' "$item" | jq -rf "$summary" 2>/dev/null
      done
    fi

    if [ "$items_emitted" -ge "$cap" ]; then
      printf 'plane: --all cap %d reached; stopping pagination\n' "$cap" >&2
      return 0
    fi

    local next_cursor has_next
    next_cursor=$(jq -r '.next_cursor // empty' "$body" 2>/dev/null)
    has_next=$(jq -r '.next_page_results // false' "$body" 2>/dev/null)
    if [ -z "$next_cursor" ] || [ "$has_next" != "true" ]; then
      return 0
    fi
    cursor="$next_cursor"
  done
}

# ---- helpers for resource libs --------------------------------------------

# _resource_parse_data_arg <arg>
# Accepts either inline JSON or @/path/to/file. Validates with jq -e type.
# On success, writes the JSON payload to a tmp file and echoes its path.
# On failure, exits 2 with a message.
_resource_parse_data_arg() {
  local arg="$1" tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/plane-data.XXXXXX")
  chmod 0600 "$tmp" 2>/dev/null || true
  _core_register_tmp "$tmp"

  if [[ "$arg" == @* ]]; then
    local src="${arg#@}"
    [ -f "$src" ] || _die 2 "--data @$src: file not found"
    cp "$src" "$tmp"
  else
    printf '%s' "$arg" > "$tmp"
  fi

  if ! jq -e type "$tmp" >/dev/null 2>&1; then
    _die 2 "--data: invalid JSON"
  fi
  printf '%s' "$tmp"
}

# _resource_scan_execute <args...>
# If --execute appears in args, export PLANE_EXECUTE=1 and echo the filtered
# args (with --execute removed) separated by ASCII unit separators. Callers
# use `mapfile -t out < <(_resource_scan_execute "$@")`. A bit roundabout,
# but keeps each resource action's parser simple.
# Exposed for tests; most resources just let _resource_call/paginate consume
# --execute directly.
_resource_scan_execute() {
  local arg
  for arg in "$@"; do
    [ "$arg" = "--execute" ] && export PLANE_EXECUTE=1
  done
  for arg in "$@"; do
    [ "$arg" = "--execute" ] && continue
    printf '%s\n' "$arg"
  done
}
