#!/usr/bin/env bash
# test/run.sh — plane skill test runner.
#
# For every file under test/ matching *.test.sh:
#   1. Create a per-test sandbox tmp dir exposed as $PLANE_TEST_TMP.
#   2. Shim `curl` to test/lib/mock_curl.sh via a per-test bin/ on PATH.
#   3. Unset any real PLANE_* or MOCK_CURL_* env that could leak in.
#   4. Run the test in a clean subshell.
#   5. Capture pass/fail.
# Also runs `bash -n` across every shell file under bin/, lib/, test/, plus
# install.sh and uninstall.sh at repo root.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$REPO_ROOT" || { printf 'test/run.sh: cannot cd to %s\n' "$REPO_ROOT" >&2; exit 1; }

MOCK_CURL_IMPL="$REPO_ROOT/test/lib/mock_curl.sh"
if [ ! -x "$MOCK_CURL_IMPL" ]; then
  printf 'test/run.sh: %s is missing or not executable\n' "$MOCK_CURL_IMPL" >&2
  exit 1
fi

pass=0
fail=0
failures=""

# ---- Syntax gate ----
printf '== syntax check ==\n'
syntax_files=""
for dir in bin lib test; do
  [ -d "$dir" ] || continue
  while IFS= read -r f; do
    syntax_files="$syntax_files $f"
  done < <(find "$dir" -type f \( -name '*.sh' -o -name plane \) 2>/dev/null | sort)
done
for f in install.sh uninstall.sh; do
  [ -f "$f" ] && syntax_files="$syntax_files $f"
done
for f in $syntax_files; do
  if bash -n "$f" 2>/dev/null; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures="$failures
  bash -n: $f"
    bash -n "$f" 2>&1 | sed 's/^/    /' >&2
  fi
done

# ---- Behavior tests ----
printf '== behavior tests ==\n'
for t in test/*.test.sh; do
  [ -f "$t" ] || continue
  name=$(basename "$t")

  # Per-test sandbox with its own PATH shim directory.
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/plane-test.XXXXXX")
  bin_dir="$sandbox/bin"
  mkdir -p "$bin_dir"
  ln -s "$MOCK_CURL_IMPL" "$bin_dir/curl"

  # Run in a subshell so exported state from one test never leaks to the next.
  (
    # Unset everything that might shape behavior if it leaked from the dev env.
    unset PLANE_API_KEY PLANE_WORKSPACE_SLUG PLANE_API_URL PLANE_CONFIG_PATH \
          PLANE_INSTALL_ROOT PLANE_CONNECT_TIMEOUT PLANE_MAX_TIME \
          PLANE_RETRY_NONIDEMPOTENT MOCK_CURL_STATUS MOCK_CURL_BODY \
          MOCK_CURL_HEADERS MOCK_CURL_EXIT MOCK_CURL_SCRIPT

    export PLANE_TEST_TMP="$sandbox"
    export PATH="$bin_dir:$PATH"
    bash "$t"
  )
  ec=$?
  if [ "$ec" -eq 0 ]; then
    printf 'PASS %s\n' "$name"
    pass=$((pass + 1))
  else
    printf 'FAIL %s (exit %d)\n' "$name" "$ec"
    fail=$((fail + 1))
    failures="$failures
  $name (exit $ec)"
  fi

  rm -rf "$sandbox"
done

printf '\n== summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'failures:%s\n' "$failures" >&2
  exit 1
fi
exit 0
