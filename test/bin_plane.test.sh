#!/usr/bin/env bash
# test/bin_plane.test.sh — dispatcher-level contracts.
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
  export PLANE_API_KEY="test-key-disp"
  rm -f "$SDIR"/curl-*
}

# 1. plane (no args) exit 0 — already covered in help tests, re-assert briefly.
out=$("$PLANE" 2>&1)
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | /usr/bin/grep -q 'Usage:'; then
  _record "plane (no args) -> root help, exit 0" 0
else
  _record "plane (no args) -> root help, exit 0" 1 "exit=$ec"
fi

# 2. Unknown top-level command -> exit 2 with guidance.
out=$("$PLANE" not-a-thing 2>&1)
ec=$?
if [ "$ec" -eq 2 ] && printf '%s' "$out" | /usr/bin/grep -q 'unknown command or resource'; then
  _record "plane <unknown> -> exit 2 with 'unknown command or resource'" 0
else
  _record "plane <unknown> -> exit 2 with 'unknown command or resource'" 1 "exit=$ec"
fi

# 3. Unknown resource action -> exit 1 (resource stub's "not implemented").
# Uses an existing resource lib so the dispatcher sources it, finds no
# matching function, and falls back to the not-implemented path.
(
  _fresh_sandbox unknown-action
  out=$("$PLANE" projects not-an-action 2>&1)
  ec=$?
  if [ "$ec" -eq 1 ] && printf '%s' "$out" | /usr/bin/grep -q 'not implemented'; then
    exit 0
  fi
  printf 'ec=%d out=%s\n' "$ec" "$out" >&2
  exit 1
) && _record "plane <resource> <unknown-action> -> exit 1, not-implemented" 0 \
  || _record "plane <resource> <unknown-action> -> exit 1, not-implemented" 1

# 4. Unknown global flag before any positional -> exit 2.
out=$("$PLANE" --no-such-flag 2>&1)
ec=$?
if [ "$ec" -eq 2 ] && printf '%s' "$out" | /usr/bin/grep -q 'unknown global flag'; then
  _record "plane --no-such-flag -> exit 2" 0
else
  _record "plane --no-such-flag -> exit 2" 1 "exit=$ec"
fi

# 5. --workspace alt propagates to the URL of an actual API call.
# Use `plane resolve MUNI-16` which hits _core_http -> mock_curl. Assert the
# captured URL contains "/workspaces/alt/".
(
  _fresh_sandbox workspace-override
  export MOCK_CURL_STATUS=200
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/2xx.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" --workspace alt resolve MUNI-16 >/dev/null 2>&1
  ec=$?
  if [ "$ec" -eq 0 ] && /usr/bin/grep -q '/workspaces/alt/' "$SDIR"/curl-argv-*.log 2>/dev/null; then
    exit 0
  fi
  printf 'ec=%d argv:\n' "$ec" >&2
  /usr/bin/cat "$SDIR"/curl-argv-*.log >&2 2>/dev/null || true
  exit 1
) && _record "--workspace alt propagates through URL construction" 0 \
  || _record "--workspace alt propagates through URL construction" 1

# 6. Meta commands precede resource dispatch: `plane version` always works
#    even when the config file is garbage.
(
  _fresh_sandbox bad-config
  printf 'not valid config\n' > "$PLANE_CONFIG_PATH"
  "$PLANE" version >/dev/null 2>&1
  [ $? -eq 0 ]
) && _record "plane version is unaffected by bad config" 0 \
  || _record "plane version is unaffected by bad config" 1

printf '\n== bin_plane.test.sh summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
[ "$fail" -gt 0 ] && { printf 'failures:%s\n' "$failures" >&2; exit 1; }
exit 0
