#!/usr/bin/env bash
set -u
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
PLANE="$REPO_ROOT/bin/plane"
pass=0; fail=0; failures=""
_record() {
  local n="$1" ok="$2" why="${3:-}"
  if [ "$ok" -eq 0 ]; then pass=$((pass + 1)); printf '  PASS %s\n' "$n"
  else fail=$((fail + 1)); failures="$failures
  $n"; [ -n "$why" ] && failures="$failures
    $why"; printf '  FAIL %s\n' "$n" >&2
  fi
}
_sandbox() {
  SDIR="$PLANE_TEST_TMP/$1"; mkdir -p "$SDIR"
  export PLANE_TEST_TMP="$SDIR" PLANE_CONFIG_PATH="$SDIR/plane"
  cat > "$PLANE_CONFIG_PATH" <<EOF
workspace_slug=testws
api_url=https://example.test
api_key_env=PLANE_API_KEY
EOF
  chmod 600 "$PLANE_CONFIG_PATH"
  export PLANE_API_KEY="k" PLANE_FORCE_PRETTY=1
  rm -f "$SDIR"/curl-*
}

# 1. Create comment: project + issue scoped.
(
  _sandbox create
  export MOCK_CURL_STATUS=201 MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/2xx.json" MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" comments create --project P-1 --issue I-1 --comment "hello" >/dev/null 2>&1
  ec=$?
  grep -q 'POST' "$SDIR"/curl-argv-*.log \
    && grep -q '/projects/P-1/issues/I-1/comments/' "$SDIR"/curl-argv-*.log \
    && [ "$ec" -eq 0 ]
) && _record "comments create -> POST issues/I-1/comments/" 0 || _record "comments create -> POST issues/I-1/comments/" 1

# 2. Missing --issue -> exit 2
(
  _sandbox no-issue
  "$PLANE" comments list --project P-1 >/dev/null 2>&1
  ec=$?
  calls=$(cat "$SDIR/curl-calls" 2>/dev/null || echo 0)
  [ "$ec" -eq 2 ] && [ "$calls" -eq 0 ]
) && _record "comments list (no --issue) -> exit 2, no network" 0 || _record "comments list (no --issue) -> exit 2, no network" 1

# 3. Delete dry-run
(
  _sandbox delete-dryrun
  "$PLANE" comments delete --project P-1 --issue I-1 C-1 >/dev/null 2>&1
  [ $? -eq 7 ]
) && _record "comments delete (no --execute) -> exit 7" 0 || _record "comments delete (no --execute) -> exit 7" 1

printf '\n== comments.test.sh ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
[ "$fail" -gt 0 ] && { printf 'failures:%s\n' "$failures" >&2; exit 1; }
exit 0
