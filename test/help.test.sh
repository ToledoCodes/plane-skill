#!/usr/bin/env bash
# test/help.test.sh — covers lazy help tree.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
PLANE="$REPO_ROOT/bin/plane"

pass=0
fail=0
failures=""

_record() {
  local name="$1" ok="$2" why="${3:-}"
  if [ "$ok" -eq 0 ]; then
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

# 1. `plane --help` lists every T1 resource by name.
out=$("$PLANE" --help 2>&1)
missing=""
for r in projects issues cycles labels states comments time-entries; do
  printf '%s' "$out" | grep -qE "^  $r " || missing="$missing $r"
done
if [ -z "$missing" ] && printf '%s' "$out" | grep -q 'Meta commands:'; then
  _record "plane --help lists all 7 T1 resources + meta commands" 0
else
  _record "plane --help lists all 7 T1 resources + meta commands" 1 \
    "missing:$missing"
fi

# 2. `plane` with no args == `plane --help`.
out2=$("$PLANE" 2>&1)
if [ "$out" = "$out2" ]; then
  _record "plane (no args) emits root help" 0
else
  _record "plane (no args) emits root help" 1 "differed from --help"
fi

# 3. `plane help` emits root help (same content).
out3=$("$PLANE" help 2>&1)
if [ "$out" = "$out3" ]; then
  _record "plane help (no arg) emits root help" 0
else
  _record "plane help (no arg) emits root help" 1 "differed from --help"
fi

# 4. `plane help issues` runs _help_resource_issues and emits issues-specific
#    help, and does NOT leak help for other resources.
out=$("$PLANE" help issues 2>&1)
if printf '%s' "$out" | grep -q 'plane issues' \
   && printf '%s' "$out" | grep -q 'list --project' \
   && ! printf '%s' "$out" | grep -q 'plane projects'; then
  _record "plane help issues emits per-resource help, no cross-talk" 0
else
  _record "plane help issues emits per-resource help, no cross-talk" 1 \
    "content: ${out:0:200}"
fi

# 5. `plane issues --help` same as `plane help issues`.
out_flag=$("$PLANE" issues --help 2>&1)
if [ "$out" = "$out_flag" ]; then
  _record "plane issues --help == plane help issues" 0
else
  _record "plane issues --help == plane help issues" 1 "differed"
fi

# 6. `plane help unknown-thing` → exit 2 + "unknown resource" stderr.
out=$("$PLANE" help nosuch 2>&1)
ec=$?
if [ "$ec" -eq 2 ] && printf '%s' "$out" | grep -qi 'unknown resource'; then
  _record "plane help <unknown> exits 2 with message" 0
else
  _record "plane help <unknown> exits 2 with message" 1 "exit=$ec out=$out"
fi

# 7. Root help does NOT source any resource lib.
# Proof by negative: define a sentinel tripwire the test injects. If a resource
# lib were sourced by --help, __PLANE_RESOURCE_ISSUES_LOADED would be 1.
# We run `plane --help` in a subshell and inspect its inherited environment
# AFTER — which requires a different pattern because env doesn't leak out.
# Instead, use `bash -x` trace and grep for a source/. of lib/issues.sh.
trace=$(bash -x "$PLANE" --help 2>&1 >/dev/null)
# bash -x prefixes lines with `+`. A SOURCE operation shows as either
# `+ . <path>` or `+ source <path>`. The mere appearance of a resource lib
# path elsewhere (e.g. in a for-loop expansion over lib/*.sh) is fine.
if printf '%s' "$trace" | grep -qE '^\+ (\.|source) [^ ]*lib/(issues|projects|cycles|labels|states|comments|time-entries)\.sh'; then
  _record "plane --help does not source any resource lib" 1 \
    "trace shows a resource lib was sourced"
else
  _record "plane --help does not source any resource lib" 0
fi

printf '\n== help.test.sh summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'failures:%s\n' "$failures" >&2
  exit 1
fi
exit 0
