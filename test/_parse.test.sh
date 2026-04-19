#!/usr/bin/env bash
# test/_parse.test.sh — exercises lib/_parse.sh helpers.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
# shellcheck source=../lib/_parse.sh
. "$REPO_ROOT/lib/_parse.sh"

pass=0
fail=0
failures=""

_record() {
  local name="$1" exit_code="$2" why="${3:-}"
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
    printf '  PASS %s\n' "$name"
  else
    fail=$((fail + 1))
    failures="${failures}
  $name"
    [ -n "$why" ] && failures="${failures}
    $why"
    printf '  FAIL %s\n' "$name" >&2
    [ -n "$why" ] && printf '    %s\n' "$why" >&2
  fi
}

# 1. Valid value passes through untouched.
out=$(_parse_clamp_limit 50 2>/dev/null)
if [ "$out" = "50" ]; then
  _record "clamp 50 -> 50" 0
else
  _record "clamp 50 -> 50" 1 "got: $out"
fi

# 2. Value above 100 clamps to 100 and warns.
stderr=$(_parse_clamp_limit 200 2>&1 >/dev/null)
out=$(_parse_clamp_limit 200 2>/dev/null)
if [ "$out" = "100" ] && printf '%s' "$stderr" | grep -q 'clamping'; then
  _record "clamp 200 -> 100 with stderr warn" 0
else
  _record "clamp 200 -> 100 with stderr warn" 1 "stdout=$out stderr=$stderr"
fi

# 3. Value below 1 clamps to 1 and warns.
stderr=$(_parse_clamp_limit 0 2>&1 >/dev/null)
out=$(_parse_clamp_limit 0 2>/dev/null)
if [ "$out" = "1" ] && printf '%s' "$stderr" | grep -q 'clamping'; then
  _record "clamp 0 -> 1 with stderr warn" 0
else
  _record "clamp 0 -> 1 with stderr warn" 1 "stdout=$out stderr=$stderr"
fi

# 4. Non-integer value exits 2.
( _parse_clamp_limit "abc" >/dev/null 2>&1 )
ec=$?
if [ "$ec" -eq 2 ]; then
  _record "clamp non-integer -> exit 2" 0
else
  _record "clamp non-integer -> exit 2" 1 "exit=$ec"
fi

# 5. Empty value exits 2.
( _parse_clamp_limit "" >/dev/null 2>&1 )
ec=$?
if [ "$ec" -eq 2 ]; then
  _record "clamp empty -> exit 2" 0
else
  _record "clamp empty -> exit 2" 1 "exit=$ec"
fi

# 6. _parse_die respects passed exit code and prints message.
out=$( ( _parse_die 9 "boom" ) 2>&1 )
ec=$?
if [ "$ec" -eq 9 ] && printf '%s' "$out" | grep -q 'boom'; then
  _record "_parse_die 9 boom -> exit 9 + msg" 0
else
  _record "_parse_die 9 boom -> exit 9 + msg" 1 "exit=$ec out=$out"
fi

# 7. _parse_warn writes to stderr, not stdout, and returns 0.
out_stdout=$(_parse_warn "heads up" 2>/dev/null)
out_stderr=$(_parse_warn "heads up" 2>&1 >/dev/null)
if [ -z "$out_stdout" ] && printf '%s' "$out_stderr" | grep -q 'heads up'; then
  _record "_parse_warn writes to stderr only" 0
else
  _record "_parse_warn writes to stderr only" 1 "stdout=$out_stdout stderr=$out_stderr"
fi

# 8. Source guard: sourcing twice does not double-define anything.
__prev_loaded=${__PLANE_PARSE_LOADED:-}
# shellcheck source=../lib/_parse.sh
. "$REPO_ROOT/lib/_parse.sh"
if [ "${__PLANE_PARSE_LOADED:-}" = "$__prev_loaded" ]; then
  _record "source guard prevents re-load" 0
else
  _record "source guard prevents re-load" 1 "loaded flag changed"
fi

printf '\n== _parse.test.sh summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'failures:%s\n' "$failures" >&2
  exit 1
fi
exit 0
