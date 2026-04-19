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

(
  _sandbox list
  export MOCK_CURL_STATUS=200 MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/projects-empty.json" MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" time-entries list --project P-1 >/dev/null 2>&1
  grep -q '/projects/P-1/time-entries/' "$SDIR"/curl-argv-*.log
) && _record "time-entries list hits /projects/P-1/time-entries/" 0 || _record "time-entries list hits /projects/P-1/time-entries/" 1

(
  _sandbox list-workspace
  export MOCK_CURL_STATUS=200 MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/projects-empty.json" MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" time-entries list-workspace >/dev/null 2>&1
  grep -q '/workspaces/testws/time-entries/' "$SDIR"/curl-argv-*.log \
    && ! grep -q '/projects/' "$SDIR"/curl-argv-*.log
) && _record "time-entries list-workspace hits /workspaces/testws/time-entries/" 0 \
  || _record "time-entries list-workspace hits /workspaces/testws/time-entries/" 1

(
  _sandbox delete-dryrun
  "$PLANE" time-entries delete --project P-1 T-1 >/dev/null 2>&1
  [ $? -eq 7 ]
) && _record "time-entries delete (no --execute) -> exit 7" 0 || _record "time-entries delete (no --execute) -> exit 7" 1

printf '\n== time-entries.test.sh ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
[ "$fail" -gt 0 ] && { printf 'failures:%s\n' "$failures" >&2; exit 1; }
exit 0
