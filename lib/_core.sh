#!/usr/bin/env bash
# Summary: core HTTP + config + secrets + retry + preflight + tmp cleanup.
# Usage: sourced by bin/plane and every resource lib.
#
# Requires bash >= 4 (associative arrays, ${BASH_SOURCE[0]}, mapfile).
[ "${__PLANE_CORE_LOADED:-0}" = "1" ] && return 0
__PLANE_CORE_LOADED=1

set -u
set -o pipefail

if [ -z "${BASH_VERSINFO+x}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'plane: bash >= 4 required (have %s)\n' "${BASH_VERSION:-unknown}" >&2
  exit 3
fi

# Source _parse.sh for warn/die helpers. Idempotent.
_CORE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=_parse.sh
. "$_CORE_DIR/_parse.sh"

# ===== Globals populated by _core_config_resolve =====
_PLANE_WORKSPACE=""
_PLANE_API_URL=""
_PLANE_API_KEY_ENV=""
_PLANE_API_KEY=""

# ===== Tmp-file cleanup =====
_CORE_TMPS=()

_core_register_tmp() {
  _CORE_TMPS+=("$1")
}

_core_cleanup_tmps() {
  local f
  if [ ${#_CORE_TMPS[@]} -gt 0 ]; then
    for f in "${_CORE_TMPS[@]}"; do
      [ -n "$f" ] && rm -f "$f" 2>/dev/null
    done
    _CORE_TMPS=()
  fi
}

trap '_core_cleanup_tmps' EXIT INT TERM

# ===== Die + inject points =====
_die() {
  # _die <code> <msg>
  printf 'plane: %s\n' "$2" >&2
  exit "$1"
}

_core_sleep() { sleep "$1"; }
_core_now()   { date +%s; }

# ===== Config resolve =====
# Precedence: CLI flag > env > ~/.claude/.plane.
_core_config_resolve() {
  local flag_workspace="" flag_api_url=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --workspace) flag_workspace="$2"; shift 2 ;;
      --api-url)   flag_api_url="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local cfg_path="${PLANE_CONFIG_PATH:-$HOME/.claude/.plane}"
  local file_workspace="" file_api_url="" file_api_key_env=""

  if [ -f "$cfg_path" ]; then
    local line key val
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        ''|\#*) continue ;;
      esac
      key="${line%%=*}"
      val="${line#*=}"
      case "$key" in
        workspace_slug) file_workspace="$val" ;;
        api_url)        file_api_url="$val" ;;
        api_key_env)    file_api_key_env="$val" ;;
      esac
    done < "$cfg_path"
  fi

  _PLANE_WORKSPACE="${flag_workspace:-${PLANE_WORKSPACE_SLUG:-$file_workspace}}"
  _PLANE_API_URL="${flag_api_url:-${PLANE_API_URL:-$file_api_url}}"
  _PLANE_API_KEY_ENV="${PLANE_API_KEY_ENV:-$file_api_key_env}"

  [ -n "$_PLANE_WORKSPACE" ]   || _die 3 "config: workspace_slug is empty"
  [ -n "$_PLANE_API_URL" ]     || _die 3 "config: api_url is empty"
  case "$_PLANE_API_URL" in
    https://*) : ;;
    *) _die 3 "config: api_url must be https:// (got: $_PLANE_API_URL)" ;;
  esac
  [ -n "$_PLANE_API_KEY_ENV" ] || _die 3 "config: api_key_env is empty"

  _PLANE_API_KEY=$(printenv "$_PLANE_API_KEY_ENV" 2>/dev/null || true)
  [ -n "$_PLANE_API_KEY" ] || _die 3 "config: env var $_PLANE_API_KEY_ENV is unset or empty"
}

# ===== Preflight =====
# Overridable in tests; default performs real checks.
_core_preflight_check() {
  command -v curl >/dev/null 2>&1 || _die 3 "preflight: curl not found"
  command -v jq >/dev/null 2>&1   || _die 3 "preflight: jq not found"
  local jq_ver
  jq_ver=$(jq --version 2>/dev/null | sed 's/^jq-//')
  case "$jq_ver" in
    1.[6-9]*|1.[1-9][0-9]*|[2-9].*|[1-9][0-9]*.*) : ;;
    *) _die 3 "preflight: jq >= 1.6 required (have '$jq_ver')" ;;
  esac
  if [ -z "${BASH_VERSINFO+x}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    _die 3 "preflight: bash >= 4 required"
  fi
}

_core_preflight() {
  [ "${__PLANE_PREFLIGHT_DONE:-0}" = "1" ] && return 0
  _core_preflight_check
  __PLANE_PREFLIGHT_DONE=1
  local cache="${TMPDIR:-/tmp}/plane-preflight-$$"
  : > "$cache"
  chmod 0600 "$cache" 2>/dev/null || true
  _core_register_tmp "$cache"
}

# ===== URL builder =====
_core_build_url() {
  local path="$1"
  case "$path" in
    http://*|https://*) printf '%s' "$path" ;;
    /api/v1/*)          printf '%s%s' "$_PLANE_API_URL" "$path" ;;
    /users/*|/workspaces/*|/auth/*)
                        printf '%s/api/v1%s' "$_PLANE_API_URL" "$path" ;;
    /*)                 printf '%s/api/v1/workspaces/%s%s' \
                                "$_PLANE_API_URL" "$_PLANE_WORKSPACE" "$path" ;;
    *)                  printf '%s/api/v1/workspaces/%s/%s' \
                                "$_PLANE_API_URL" "$_PLANE_WORKSPACE" "$path" ;;
  esac
}

_core_is_idempotent() {
  case "$1" in
    GET|HEAD|PUT|DELETE|OPTIONS) return 0 ;;
    *) return 1 ;;
  esac
}

# Parse X-RateLimit-Reset (relative seconds) or Retry-After from a headers file.
# Echo clamped wait in [1, 60]; default 4 if neither header present or parseable.
_core_parse_retry_after() {
  local hdrs="$1" reset="" retry_after=""
  if [ -f "$hdrs" ]; then
    reset=$(grep -i '^X-RateLimit-Reset:' "$hdrs" 2>/dev/null | tail -1 \
              | awk -F': *' '{print $2}' | tr -d '\r' | tr -d '[:space:]')
    retry_after=$(grep -i '^Retry-After:' "$hdrs" 2>/dev/null | tail -1 \
                    | awk -F': *' '{print $2}' | tr -d '\r' | tr -d '[:space:]')
  fi
  local wait=""
  case "$reset" in
    ''|*[!0-9]*) ;;
    *) wait="$reset" ;;
  esac
  if [ -z "$wait" ]; then
    case "$retry_after" in
      ''|*[!0-9]*) ;;
      *) wait="$retry_after" ;;
    esac
  fi
  [ -z "$wait" ] && wait=4
  [ "$wait" -lt 1 ] && wait=1
  [ "$wait" -gt 60 ] && wait=60
  printf '%s' "$wait"
}

# ===== HTTP =====
# Usage: _core_http <METHOD> <path> [--body <file>] [--query k=v]
# Returns: "<status>\t<body-tmp-path>" on success; exits with mapped code on error.
_core_http() {
  local method="$1"; shift
  local path="$1"; shift
  local body_file=""
  local query_args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --body)  body_file="$2"; shift 2 ;;
      --query) query_args+=("$2"); shift 2 ;;
      *) shift ;;
    esac
  done

  local url
  url=$(_core_build_url "$path")

  if [ ${#query_args[@]} -gt 0 ]; then
    local q qs=""
    for q in "${query_args[@]}"; do
      qs="${qs}${qs:+&}${q}"
    done
    case "$url" in
      *\?*) url="${url}&${qs}" ;;
      *)    url="${url}?${qs}" ;;
    esac
  fi

  local retries_429=3
  local attempt=0
  local status body hdrs

  while :; do
    attempt=$((attempt + 1))
    body=$(mktemp "${TMPDIR:-/tmp}/plane-body.XXXXXX")
    hdrs=$(mktemp "${TMPDIR:-/tmp}/plane-hdrs.XXXXXX")
    chmod 0600 "$body" "$hdrs" 2>/dev/null || true
    _core_register_tmp "$body"
    _core_register_tmp "$hdrs"

    # Curl config on stdin: only place the API key appears.
    local cfg="header = \"X-API-Key: $_PLANE_API_KEY\""
    if [ -n "$body_file" ]; then
      cfg="$cfg
header = \"Content-Type: application/json\""
    fi

    local curl_args=(
      -sS
      -o "$body"
      -D "$hdrs"
      -w '%{http_code}'
      --config -
      --connect-timeout "${PLANE_CONNECT_TIMEOUT:-10}"
      --max-time "${PLANE_MAX_TIME:-60}"
      -X "$method"
    )
    [ -n "$body_file" ] && curl_args+=(--data-binary "@$body_file")
    curl_args+=("$url")

    # env -u keeps the API key out of curl's inherited env. stdin carries the
    # config. argv never sees the key.
    local curl_ec=0
    status=$(printf '%s\n' "$cfg" \
      | env -u "$_PLANE_API_KEY_ENV" -u PLANE_API_KEY \
          curl "${curl_args[@]}" 2>/dev/null) || curl_ec=$?

    if [ "$curl_ec" -ne 0 ]; then
      case "$curl_ec" in
        6|7|28|35|56|60) _die 8 "transport: curl exit $curl_ec" ;;
        *)               _die 1 "curl exited $curl_ec" ;;
      esac
    fi

    case "$status" in
      2*)
        printf '%s\t%s' "$status" "$body"
        return 0
        ;;
      429)
        if [ "$retries_429" -le 0 ]; then
          _die 5 "rate-limited after retries (429)"
        fi
        retries_429=$((retries_429 - 1))
        local wait
        wait=$(_core_parse_retry_after "$hdrs")
        _core_sleep "$wait"
        continue
        ;;
      401|403) _die 4 "$status unauthorized/forbidden" ;;
      404)     _die 9 "404 not found ($url)" ;;
      409)     _die 10 "409 conflict" ;;
      400|422) _die 2 "$status bad request" ;;
      5*)
        if _core_is_idempotent "$method" || [ "${PLANE_RETRY_NONIDEMPOTENT:-0}" = "1" ]; then
          if [ "$attempt" -lt 2 ]; then
            _core_sleep 2
            continue
          fi
        fi
        _die 6 "$status server error"
        ;;
      3*)
        _die 1 "$status redirect without --follow-redirects"
        ;;
      *)
        _die 1 "unexpected status $status"
        ;;
    esac
  done
}

# ===== JSON body builder =====
# Usage: body=$(_core_jq_body key1 val1 [key2 val2 ...])
# All values are passed as strings via --arg. For numeric/boolean payload
# values, callers must use jq directly.
_core_jq_body() {
  local args=()
  local expr="{}"
  while [ $# -gt 0 ]; do
    local key="$1" val="$2"; shift 2
    args+=(--arg "$key" "$val")
    expr="${expr} + {\"$key\": \$$key}"
  done
  jq -n "${args[@]}" "$expr"
}

# ===== Redaction =====
# Echo the body with sensitive keys masked, truncated to 2KB.
_core_redact() {
  local path="$1"
  [ -f "$path" ] || { printf ''; return 0; }

  local out
  out=$(jq --compact-output '
    def _is_sensitive(k):
      k | test("^(api_key|.*_key|token|password|secret|Authorization|ssn|credit_card|phone|.*_phone)$"; "i");
    def mask:
      if type == "object" then
        with_entries(if _is_sensitive(.key) then .value = "<redacted>" else . end)
      else . end;
    walk(mask)
  ' "$path" 2>/dev/null)

  if [ -z "$out" ]; then
    # Non-JSON body: emit raw (still truncated below).
    out=$(cat "$path")
  fi

  local limit=2048
  if [ "${#out}" -gt "$limit" ]; then
    out="${out:0:$limit}…[truncated]"
  fi
  printf '%s' "$out"
}
