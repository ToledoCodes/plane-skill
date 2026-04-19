#!/usr/bin/env bash
# Summary: environment preflight for the plane CLI (curl, jq, bash, config, auth, connectivity).
# Usage:   plane doctor
[ "${__PLANE_DOCTOR_LOADED:-0}" = "1" ] && return 0
__PLANE_DOCTOR_LOADED=1

# _doctor_pass / _doctor_fail: print and record. First failing check's exit
# code wins.
_DOCTOR_FIRST_FAIL_CODE=0
_doctor_pass() {
  printf 'PASS: %s\n' "$1"
}
_doctor_fail() {
  # _doctor_fail <exit_code> <label> [<detail>]
  local code="$1" label="$2" detail="${3:-}"
  if [ -n "$detail" ]; then
    printf 'FAIL: %s (%s)\n' "$label" "$detail"
  else
    printf 'FAIL: %s\n' "$label"
  fi
  if [ "$_DOCTOR_FIRST_FAIL_CODE" -eq 0 ]; then
    _DOCTOR_FIRST_FAIL_CODE="$code"
  fi
}

_doctor_cmd() {
  # Run all 8 checks per R4a. Return 0 on all-pass, first-failure's code otherwise.
  _DOCTOR_FIRST_FAIL_CODE=0

  # 1. curl present and executable.
  if command -v curl >/dev/null 2>&1; then
    _doctor_pass "curl present"
  else
    _doctor_fail 3 "curl present" "command not found"
  fi

  # 2. jq present, version >= 1.6.
  if command -v jq >/dev/null 2>&1; then
    local jq_ver
    jq_ver=$(jq --version 2>/dev/null | sed 's/^jq-//')
    case "$jq_ver" in
      1.[6-9]*|1.[1-9][0-9]*|[2-9].*|[1-9][0-9]*.*)
        _doctor_pass "jq present (>= 1.6): $jq_ver"
        ;;
      *)
        _doctor_fail 3 "jq >= 1.6" "have $jq_ver"
        ;;
    esac
  else
    _doctor_fail 3 "jq present" "command not found"
  fi

  # 3. bash version >= 4.
  local bash_major
  bash_major="${BASH_VERSINFO[0]:-0}"
  if [ "$bash_major" -ge 4 ]; then
    _doctor_pass "bash >= 4 (have ${BASH_VERSION:-unknown})"
  else
    _doctor_fail 3 "bash >= 4" "have ${BASH_VERSION:-unknown}; macOS? run: brew install bash"
  fi

  # 4. ~/.claude/.plane exists and mode 0600 (unless all three env overrides set).
  local cfg_path="${PLANE_CONFIG_PATH:-$HOME/.claude/.plane}"
  local env_override=0
  if [ -n "${PLANE_WORKSPACE_SLUG:-}" ] \
     && [ -n "${PLANE_API_URL:-}" ] \
     && [ -n "${PLANE_API_KEY_ENV:-}" ]; then
    env_override=1
  fi
  if [ -f "$cfg_path" ]; then
    local mode=""
    mode=$(stat -f '%Lp' "$cfg_path" 2>/dev/null) \
      || mode=$(stat -c '%a' "$cfg_path" 2>/dev/null) \
      || mode=""
    case "$mode" in
      600|400) _doctor_pass "config $cfg_path exists (mode $mode)" ;;
      '')      _doctor_pass "config $cfg_path exists (mode unknown)" ;;
      *)       _doctor_fail 3 "config mode 0600" "$cfg_path is $mode (run: chmod 600 $cfg_path)" ;;
    esac
  elif [ "$env_override" -eq 1 ]; then
    _doctor_pass "config env overrides set (PLANE_WORKSPACE_SLUG/API_URL/API_KEY_ENV)"
  else
    _doctor_fail 3 "config present" "missing $cfg_path"
  fi

  # 5-7. Resolved workspace_slug / api_url / api_key_env non-empty; api_url https.
  # Reuse _core_config_resolve when possible, but isolate so a failure doesn't abort.
  local resolved_ok=0
  local sub_exit=0
  (
    _core_config_resolve
  ) >/dev/null 2>&1
  sub_exit=$?
  if [ "$sub_exit" -eq 0 ]; then
    _core_config_resolve >/dev/null 2>&1 || true
    _doctor_pass "workspace_slug + api_url + api_key_env resolve"
    _doctor_pass "api_url is https://"
    # 6. Env var named by api_key_env is set (don't echo the value).
    if [ -n "${_PLANE_API_KEY:-}" ]; then
      _doctor_pass "env var \$${_PLANE_API_KEY_ENV:-?} is set (value not echoed)"
    else
      _doctor_fail 3 "env var set" "named by api_key_env is empty"
    fi
    resolved_ok=1
  else
    _doctor_fail 3 "config resolves" "see stderr of _core_config_resolve"
    # Skip downstream checks that require resolved config.
    _doctor_fail 3 "api_url is https://" "config unresolved"
    _doctor_fail 3 "env var set" "config unresolved"
  fi

  # 8. Connectivity: GET /workspaces/<slug>/members/me/.
  if [ "$resolved_ok" -eq 1 ]; then
    # _core_http exits (via _die) on failure, so call it in a subshell and
    # capture the resulting exit code without killing our own shell.
    local http_ec=0
    # shellcheck disable=SC2034  # command substitution output discarded; we only want the exit code
    local _discard
    _discard=$( _core_http GET /members/me/ 2>/dev/null ) || http_ec=$?
    case "$http_ec" in
      0)  _doctor_pass "connectivity GET /members/me/ (2xx)" ;;
      4)  _doctor_fail 4 "connectivity GET /members/me/" "401/403 — bad API key or permissions" ;;
      8)  _doctor_fail 8 "connectivity GET /members/me/" "transport error (DNS/TLS/timeout)" ;;
      *)  _doctor_fail "$http_ec" "connectivity GET /members/me/" "exit code $http_ec" ;;
    esac
  else
    _doctor_fail 3 "connectivity GET /members/me/" "config unresolved — skipped"
  fi

  return "$_DOCTOR_FIRST_FAIL_CODE"
}
