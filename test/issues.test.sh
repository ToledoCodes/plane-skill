#!/usr/bin/env bash
# test/issues.test.sh — per-resource smoke over the _resource helper.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
PLANE="$REPO_ROOT/bin/plane"

pass=0; fail=0; failures=""
_record() {
  local n="$1" ok="$2" why="${3:-}"
  if [ "$ok" -eq 0 ]; then pass=$((pass + 1)); printf '  PASS %s\n' "$n"
  else fail=$((fail + 1)); failures="$failures
  $n"; [ -n "$why" ] && failures="$failures
    $why"; printf '  FAIL %s\n' "$n" >&2; [ -n "$why" ] && printf '    %s\n' "$why" >&2
  fi
}
_sandbox() {
  SDIR="$PLANE_TEST_TMP/$1"; mkdir -p "$SDIR"
  export PLANE_TEST_TMP="$SDIR"
  export PLANE_CONFIG_PATH="$SDIR/plane"
  cat > "$PLANE_CONFIG_PATH" <<EOF
workspace_slug=testws
api_url=https://example.test
api_key_env=PLANE_API_KEY
EOF
  chmod 600 "$PLANE_CONFIG_PATH"
  export PLANE_API_KEY="k"
  export PLANE_FORCE_PRETTY=1
  rm -f "$SDIR"/curl-*
}

# 1. list hits the project-scoped issues endpoint
(
  _sandbox list
  export MOCK_CURL_STATUS=200 MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/projects-empty.json" MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" issues list --project P-1 >/dev/null 2>&1
  grep -q '/workspaces/testws/projects/P-1/issues/' "$SDIR"/curl-argv-*.log
) && _record "issues list --project hits /projects/P-1/issues/" 0 \
  || _record "issues list --project hits /projects/P-1/issues/" 1

# 2. missing --project -> exit 2 pre-network
(
  _sandbox no-project
  "$PLANE" issues list >/dev/null 2>&1
  ec=$?
  calls=$(cat "$SDIR/curl-calls" 2>/dev/null || echo 0)
  [ "$ec" -eq 2 ] && [ "$calls" -eq 0 ]
) && _record "issues list (no --project) -> exit 2, no network" 0 \
  || _record "issues list (no --project) -> exit 2, no network" 1

# 3. delete dry-run
(
  _sandbox delete-dryrun
  "$PLANE" issues delete --project P-1 I-1 >/dev/null 2>&1
  ec=$?
  calls=$(cat "$SDIR/curl-calls" 2>/dev/null || echo 0)
  [ "$ec" -eq 7 ] && [ "$calls" -eq 0 ]
) && _record "issues delete (no --execute) -> dry-run exit 7" 0 \
  || _record "issues delete (no --execute) -> dry-run exit 7" 1

# 4. delete --execute hits the right path
(
  _sandbox delete-exec
  export MOCK_CURL_STATUS=204 MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/2xx.json" MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" issues delete --project P-1 I-1 --execute >/dev/null 2>&1
  grep -q '/workspaces/testws/projects/P-1/issues/I-1/' "$SDIR"/curl-argv-*.log 2>/dev/null \
    && grep -q 'DELETE' "$SDIR"/curl-argv-*.log 2>/dev/null
) && _record "issues delete --execute -> DELETE /projects/P-1/issues/I-1/" 0 \
  || _record "issues delete --execute -> DELETE /projects/P-1/issues/I-1/" 1

# 5. search uses workspace-scope path
(
  _sandbox search
  export MOCK_CURL_STATUS=200 MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/projects-empty.json" MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" issues search --query bug >/dev/null 2>&1
  grep -q '/workspaces/testws/issues/search/' "$SDIR"/curl-argv-*.log
) && _record "issues search hits /issues/search/" 0 \
  || _record "issues search hits /issues/search/" 1

printf '\n== issues.test.sh ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
[ "$fail" -gt 0 ] && { printf 'failures:%s\n' "$failures" >&2; exit 1; }
exit 0
