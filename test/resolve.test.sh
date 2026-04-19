#!/usr/bin/env bash
# test/resolve.test.sh — plane resolve success + failure paths.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
PLANE="$REPO_ROOT/bin/plane"

pass=0
fail=0
failures=""

_record() {
  local name="$1" ok="$2" why="${3:-}"
  if [ "$ok" -eq 0 ]; then
    pass=$((pass + 1)); printf '  PASS %s\n' "$name"
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

_fresh_sandbox() {
  SDIR="$PLANE_TEST_TMP/$1"
  mkdir -p "$SDIR"
  export PLANE_TEST_TMP="$SDIR"
  export PLANE_CONFIG_PATH="$SDIR/plane"
  cat > "$PLANE_CONFIG_PATH" <<EOF
workspace_slug=testws
api_url=https://example.test
api_key_env=PLANE_API_KEY
EOF
  chmod 600 "$PLANE_CONFIG_PATH"
  export PLANE_API_KEY="test-key-resolve"
  rm -f "$SDIR"/curl-*
}

# --- Scenario 1: 200 -> success, emits body, exit 0 -------------
(
  _fresh_sandbox resolve-200
  export MOCK_CURL_STATUS=200
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/2xx.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  # Pipe stdout so output hits the JSON branch, not the TTY summary.
  out=$("$PLANE" resolve MUNI-16 2>/dev/null)
  ec=$?
  if [ "$ec" -eq 0 ] && printf '%s' "$out" | /opt/homebrew/bin/jq -e '.id' >/dev/null 2>&1; then
    # URL hit should include /issues/MUNI-16/
    if /usr/bin/grep -q 'issues/MUNI-16/' "$SDIR"/curl-argv-*.log 2>/dev/null; then
      exit 0
    fi
    printf 'argv did not include issues/MUNI-16/\n' >&2
    exit 1
  fi
  printf 'ec=%d out=%s\n' "$ec" "$out" >&2
  exit 1
) && _record "resolve MUNI-16 -> 200 JSON body + /issues/MUNI-16/ hit" 0 \
  || _record "resolve MUNI-16 -> 200 JSON body + /issues/MUNI-16/ hit" 1

# --- Scenario 2: no argument -> exit 2 --------------------------
(
  _fresh_sandbox resolve-noarg
  out=$("$PLANE" resolve 2>&1)
  ec=$?
  if [ "$ec" -eq 2 ] && printf '%s' "$out" | /usr/bin/grep -qi 'identifier'; then
    exit 0
  fi
  printf 'ec=%d out=%s\n' "$ec" "$out" >&2
  exit 1
) && _record "resolve (no arg) -> exit 2 with 'identifier' in stderr" 0 \
  || _record "resolve (no arg) -> exit 2 with 'identifier' in stderr" 1

# --- Scenario 3: malformed identifier -> exit 2 (no network) ---
(
  _fresh_sandbox resolve-malformed
  out=$("$PLANE" resolve NOTACODE 2>&1)
  ec=$?
  # Must not have made a network call (no curl invocation happens for
  # obvious-bad-input; plane prints guidance and exits).
  calls=$(cat "$SDIR/curl-calls" 2>/dev/null || echo 0)
  if [ "$ec" -eq 2 ] && [ "$calls" -eq 0 ]; then
    exit 0
  fi
  printf 'ec=%d calls=%s out=%s\n' "$ec" "$calls" "$out" >&2
  exit 1
) && _record "resolve <malformed> -> exit 2, no network call" 0 \
  || _record "resolve <malformed> -> exit 2, no network call" 1

# --- Scenario 4: 404 -> exit 9 ---------------------------------
(
  _fresh_sandbox resolve-404
  export MOCK_CURL_STATUS=404
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/404.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" resolve MUNI-9999 >/dev/null 2>&1
  ec=$?
  [ "$ec" -eq 9 ]
) && _record "resolve <missing> -> 404 -> exit 9" 0 \
  || _record "resolve <missing> -> 404 -> exit 9" 1

printf '\n== resolve.test.sh summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
[ "$fail" -gt 0 ] && { printf 'failures:%s\n' "$failures" >&2; exit 1; }
exit 0
