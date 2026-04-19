#!/usr/bin/env bash
# test/run.sh — Unit 1 stub test runner. Real runner arrives in Unit 2
# (PATH-shim curl mock, exit-code fixtures, etc.).
#
# For now: iterate test/*.test.sh, run each in a clean subshell, print
# pass/fail, and accumulate an overall exit code. Also run `bash -n`
# across every *.sh under bin/, lib/, and test/.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$REPO_ROOT"

pass=0
fail=0
failures=""

printf '== syntax check ==\n'
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures="$failures\n  bash -n: $f"
    bash -n "$f" 2>&1 | sed 's/^/    /' >&2
  fi
done < <(find bin lib test -type f -name '*.sh' -o -path './bin/plane' 2>/dev/null | sort -u)

# install.sh / uninstall.sh live at repo root.
for f in install.sh uninstall.sh; do
  [ -f "$f" ] || continue
  if bash -n "$f" 2>/dev/null; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures="$failures\n  bash -n: $f"
    bash -n "$f" 2>&1 | sed 's/^/    /' >&2
  fi
done

printf '== behavior tests ==\n'
for t in test/*.test.sh; do
  [ -f "$t" ] || continue
  name=$(basename "$t")
  if ( bash "$t" ); then
    printf 'PASS %s\n' "$name"
    pass=$((pass + 1))
  else
    printf 'FAIL %s (exit %d)\n' "$name" "$?"
    fail=$((fail + 1))
    failures="$failures\n  $name"
  fi
done

printf '\n== summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'failures:%b\n' "$failures" >&2
  exit 1
fi
exit 0
