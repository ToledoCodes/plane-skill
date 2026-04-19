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
  export PLANE_TEST_TMP="$SDIR"
  export PLANE_CONFIG_PATH="$SDIR/plane"
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
  "$PLANE" labels list --project P-1 >/dev/null 2>&1
  grep -q '/workspaces/testws/projects/P-1/labels/' "$SDIR"/curl-argv-*.log
) && _record "labels list hits /projects/P-1/labels/" 0 || _record "labels list hits /projects/P-1/labels/" 1

(
  _sandbox delete-dryrun
  "$PLANE" labels delete --project P-1 L-1 >/dev/null 2>&1
  [ $? -eq 7 ]
) && _record "labels delete (no --execute) -> exit 7" 0 || _record "labels delete (no --execute) -> exit 7" 1

(
  _sandbox create
  export MOCK_CURL_STATUS=201 MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/2xx.json" MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" labels create --project P-1 --name bug --color "#ff0000" >/dev/null 2>&1
  ec=$?
  grep -q 'POST' "$SDIR"/curl-argv-*.log \
    && grep -q '/projects/P-1/labels/' "$SDIR"/curl-argv-*.log \
    && [ "$ec" -eq 0 ]
) && _record "labels create -> POST /projects/P-1/labels/" 0 || _record "labels create -> POST /projects/P-1/labels/" 1

printf '\n== labels.test.sh ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
[ "$fail" -gt 0 ] && { printf 'failures:%s\n' "$failures" >&2; exit 1; }
exit 0
