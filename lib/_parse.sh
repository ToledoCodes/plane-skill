#!/usr/bin/env bash
# Summary: shared arg-parse helpers (warn, die, clamp-limit).
# Usage: sourced by bin/plane and resource libs; never executed directly.
#
# This file is intentionally minimal. Per-resource arg parsing lives in each
# resource lib using a plain `while/case` pattern (see the plan's parsing
# snippet). Anything that turns out to be genuinely shared lives here after
# the Rule of Three.
#
# Contracts:
#   _parse_warn <msg>        — stderr `plane: <msg>`; returns 0.
#   _parse_die  <code> <msg> — stderr `plane: <msg>`; exits with <code>.
#   _parse_clamp_limit <n>   — validates n is a positive integer, clamps to
#                              [1, 100], warns on clamp, echoes result.
[ "${__PLANE_PARSE_LOADED:-0}" = "1" ] && return 0
__PLANE_PARSE_LOADED=1

_parse_warn() {
  printf 'plane: %s\n' "$1" >&2
}

_parse_die() {
  printf 'plane: %s\n' "$2" >&2
  exit "$1"
}

_parse_clamp_limit() {
  local v="$1"
  case "$v" in
    ''|*[!0-9]*)
      _parse_die 2 "--limit must be a positive integer (got: '$v')"
      ;;
  esac
  if [ "$v" -lt 1 ]; then
    _parse_warn "--limit $v < 1; clamping to 1"
    printf '%s' 1
    return 0
  fi
  if [ "$v" -gt 100 ]; then
    _parse_warn "--limit $v > 100; clamping to 100"
    printf '%s' 100
    return 0
  fi
  printf '%s' "$v"
}
