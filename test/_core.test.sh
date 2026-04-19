#!/usr/bin/env bash
# test/_core.test.sh — exercises lib/_core.sh.
#
# Every scenario:
#   - starts in a clean $PLANE_TEST_TMP provided by test/run.sh
#   - overrides _core_sleep and _core_now where timing matters
#   - asserts exit code, argv/stdin/env captures, and cleanup state
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
# shellcheck source=../lib/_core.sh
. "$REPO_ROOT/lib/_core.sh"

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

# --- per-scenario isolation -------------------------------------------------
# Each scenario runs in a subshell with its own config file, argv logs, and
# mock_curl behavior. Helpers below set up a fresh state.

_scenario() {
  # $1 = scenario subdir name under $PLANE_TEST_TMP
  SDIR="$PLANE_TEST_TMP/$1"
  mkdir -p "$SDIR"
  CFG="$SDIR/plane"
  export PLANE_CONFIG_PATH="$CFG"
  cat > "$CFG" <<EOF
workspace_slug=testws
api_url=https://example.test
api_key_env=PLANE_API_KEY
EOF
  chmod 600 "$CFG"
  export PLANE_API_KEY="test-key-SECRET-$1"
  # Fresh argv logs per scenario.
  export PLANE_TEST_TMP_SCENARIO="$SDIR"
  # Point mock_curl at this subdir by overriding PLANE_TEST_TMP just for curl.
  # (We keep the top-level PLANE_TEST_TMP untouched so that sleep logs etc.
  #  don't collide.)
  export PLANE_TEST_TMP="$SDIR"
  rm -f "$SDIR"/curl-*
  rm -f "$SDIR"/sleeps "$SDIR"/preflight-calls
  # Drop any cached preflight from a previous scenario.
  unset __PLANE_PREFLIGHT_DONE
  rm -f "${TMPDIR:-/tmp}/plane-preflight-$$" 2>/dev/null || true
}

# --- Config resolution -----------------------------------------------------

printf '== config resolution ==\n'

(
  _scenario cfg-file
  _core_config_resolve
  [ "$_PLANE_WORKSPACE" = "testws" ] \
    && [ "$_PLANE_API_URL" = "https://example.test" ] \
    && [ "$_PLANE_API_KEY_ENV" = "PLANE_API_KEY" ] \
    && [ "$_PLANE_API_KEY" = "$PLANE_API_KEY" ]
) && _record "config from file" 0 || _record "config from file" 1

(
  _scenario cfg-env-only
  rm -f "$PLANE_CONFIG_PATH"
  export PLANE_WORKSPACE_SLUG=envws
  export PLANE_API_URL=https://env.test
  export PLANE_API_KEY_ENV=PLANE_API_KEY
  _core_config_resolve
  [ "$_PLANE_WORKSPACE" = "envws" ] \
    && [ "$_PLANE_API_URL" = "https://env.test" ]
) && _record "config from env only (file absent)" 0 || _record "config from env only (file absent)" 1

(
  _scenario cfg-flag-override
  _core_config_resolve --workspace alt --api-url https://flag.test
  [ "$_PLANE_WORKSPACE" = "alt" ] \
    && [ "$_PLANE_API_URL" = "https://flag.test" ]
) && _record "flag overrides file+env" 0 || _record "flag overrides file+env" 1

(
  _scenario cfg-http-rejected
  cat > "$PLANE_CONFIG_PATH" <<EOF
workspace_slug=w
api_url=http://insecure.test
api_key_env=PLANE_API_KEY
EOF
  out=$( _core_config_resolve 2>&1 )
  ec=$?
  [ "$ec" -eq 3 ] && printf '%s' "$out" | grep -qi 'https'
) && _record "http:// api_url -> exit 3 'https'" 0 || _record "http:// api_url -> exit 3 'https'" 1

(
  _scenario cfg-missing-key
  cat > "$PLANE_CONFIG_PATH" <<EOF
workspace_slug=w
api_url=https://x.test
api_key_env=PLANE_API_KEY_MISSING_XYZ
EOF
  unset PLANE_API_KEY_MISSING_XYZ
  out=$( _core_config_resolve 2>&1 )
  ec=$?
  [ "$ec" -eq 3 ] && printf '%s' "$out" | grep -q 'PLANE_API_KEY_MISSING_XYZ'
) && _record "missing env var named by api_key_env -> exit 3 naming it" 0 || _record "missing env var named by api_key_env -> exit 3 naming it" 1

# --- _core_http status dispatch --------------------------------------------

printf '== _core_http status codes ==\n'

# Helper to run one HTTP scenario.
_http_call() {
  # Usage: _http_call <METHOD> <path> — prints "status<TAB>body_path" on success
  # or exits with the mapped code.
  _core_config_resolve
  _core_http "$@"
}

_assert_exit() {
  # _assert_exit <label> <expected_code> <subshell_exit>
  local label="$1" expected="$2" got="$3"
  if [ "$got" -eq "$expected" ]; then
    _record "$label" 0
  else
    _record "$label" 1 "expected $expected, got $got"
  fi
}

_run_single_call() {
  # Set up a one-shot mock response via env vars, then run _core_http.
  # $1=status $2=body $3=method $4=path
  local status="$1" body="$2" method="$3" path="$4"
  export MOCK_CURL_STATUS="$status"
  export MOCK_CURL_BODY="$body"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  unset MOCK_CURL_SCRIPT MOCK_CURL_EXIT
  # Override the sleeper so retry scenarios don't actually sleep.
  _core_sleep() { printf 'slept=%s\n' "$1" >> "$PLANE_TEST_TMP/sleeps"; }
  ( _http_call "$method" "$path" >/dev/null 2>&1 )
}

(
  _scenario http-200
  _run_single_call 200 "$REPO_ROOT/test/fixtures/api/2xx.json" GET /projects/
  ec=$?
  _assert_exit "200 -> exit 0" 0 "$ec"
)

(
  _scenario http-400
  _run_single_call 400 "$REPO_ROOT/test/fixtures/api/400.json" GET /projects/
  ec=$?
  _assert_exit "400 -> exit 2" 2 "$ec"
)

(
  _scenario http-401
  _run_single_call 401 "$REPO_ROOT/test/fixtures/api/401.json" GET /projects/
  ec=$?
  _assert_exit "401 -> exit 4" 4 "$ec"
)

(
  _scenario http-404
  _run_single_call 404 "$REPO_ROOT/test/fixtures/api/404.json" GET /projects/XYZ
  ec=$?
  _assert_exit "404 -> exit 9" 9 "$ec"
)

(
  _scenario http-409
  _run_single_call 409 "$REPO_ROOT/test/fixtures/api/409.json" POST /projects/
  ec=$?
  _assert_exit "409 -> exit 10" 10 "$ec"
)

(
  _scenario http-422
  _run_single_call 422 "$REPO_ROOT/test/fixtures/api/422.json" POST /projects/
  ec=$?
  _assert_exit "422 -> exit 2" 2 "$ec"
)

(
  _scenario http-3xx
  # No --follow-redirects: 3xx is unexpected → exit 1.
  _run_single_call 302 "$REPO_ROOT/test/fixtures/api/2xx.json" GET /projects/
  ec=$?
  _assert_exit "302 without --follow-redirects -> exit 1" 1 "$ec"
)

# --- transport errors (curl non-zero exit) ---------------------------------

printf '== transport errors ==\n'

(
  _scenario transport-28
  export MOCK_CURL_EXIT=28
  export MOCK_CURL_STATUS=0
  _core_sleep() { :; }
  ( _core_config_resolve && _core_http GET /projects/ >/dev/null 2>&1 )
  ec=$?
  _assert_exit "curl exit 28 (timeout) -> exit 8" 8 "$ec"
)

(
  _scenario transport-35
  export MOCK_CURL_EXIT=35
  export MOCK_CURL_STATUS=0
  _core_sleep() { :; }
  ( _core_config_resolve && _core_http GET /projects/ >/dev/null 2>&1 )
  ec=$?
  _assert_exit "curl exit 35 (TLS) -> exit 8" 8 "$ec"
)

# --- retry matrix ----------------------------------------------------------

printf '== retry matrix ==\n'

(
  _scenario retry-500-get
  # First call 500, second call 200. Uses MOCK_CURL_SCRIPT.
  script="$PLANE_TEST_TMP/script.sh"
  cat > "$script" <<'EOF'
#!/bin/sh
case "$1" in
  1) printf 'STATUS=500 BODY=%s/test/fixtures/api/500.json\n' "$REPO_ROOT" ;;
  *) printf 'STATUS=200 BODY=%s/test/fixtures/api/2xx.json\n' "$REPO_ROOT" ;;
esac
EOF
  chmod +x "$script"
  export REPO_ROOT
  export MOCK_CURL_SCRIPT="$script"
  unset MOCK_CURL_STATUS MOCK_CURL_BODY
  _core_sleep() { printf 'slept=%s\n' "$1" >> "$PLANE_TEST_TMP/sleeps"; }
  ( _core_config_resolve && _core_http GET /projects/ >/dev/null 2>&1 )
  ec=$?
  calls=$(cat "$PLANE_TEST_TMP/curl-calls" 2>/dev/null || echo 0)
  [ "$ec" -eq 0 ] && [ "$calls" -eq 2 ]
) && _record "500 on GET: retry once, second 200 -> exit 0, 2 calls" 0 \
  || _record "500 on GET: retry once, second 200 -> exit 0, 2 calls" 1

(
  _scenario retry-500-post
  _run_single_call 500 "$REPO_ROOT/test/fixtures/api/500.json" POST /projects/
  ec=$?
  calls=$(cat "$PLANE_TEST_TMP/curl-calls" 2>/dev/null || echo 0)
  [ "$ec" -eq 6 ] && [ "$calls" -eq 1 ]
) && _record "500 on POST: no retry -> exit 6, 1 call" 0 \
  || _record "500 on POST: no retry -> exit 6, 1 call" 1

(
  _scenario retry-500-post-override
  export PLANE_RETRY_NONIDEMPOTENT=1
  script="$PLANE_TEST_TMP/script.sh"
  cat > "$script" <<'EOF'
#!/bin/sh
case "$1" in
  1) printf 'STATUS=500 BODY=%s/test/fixtures/api/500.json\n' "$REPO_ROOT" ;;
  *) printf 'STATUS=200 BODY=%s/test/fixtures/api/2xx.json\n' "$REPO_ROOT" ;;
esac
EOF
  chmod +x "$script"
  export REPO_ROOT
  export MOCK_CURL_SCRIPT="$script"
  unset MOCK_CURL_STATUS MOCK_CURL_BODY
  _core_sleep() { :; }
  ( _core_config_resolve && _core_http POST /projects/ >/dev/null 2>&1 )
  ec=$?
  calls=$(cat "$PLANE_TEST_TMP/curl-calls" 2>/dev/null || echo 0)
  [ "$ec" -eq 0 ] && [ "$calls" -eq 2 ]
) && _record "500 on POST with PLANE_RETRY_NONIDEMPOTENT=1: 2 calls, 0" 0 \
  || _record "500 on POST with PLANE_RETRY_NONIDEMPOTENT=1: 2 calls, 0" 1

(
  _scenario retry-429-exhaust
  export MOCK_CURL_STATUS=429
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/429.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/rate-limit-headers.txt"
  unset MOCK_CURL_SCRIPT MOCK_CURL_EXIT
  _core_sleep() { printf 'slept=%s\n' "$1" >> "$PLANE_TEST_TMP/sleeps"; }
  ( _core_config_resolve && _core_http GET /projects/ >/dev/null 2>&1 )
  ec=$?
  calls=$(cat "$PLANE_TEST_TMP/curl-calls" 2>/dev/null || echo 0)
  sleeps=$(wc -l < "$PLANE_TEST_TMP/sleeps" 2>/dev/null | tr -d ' ')
  [ "$ec" -eq 5 ] && [ "$calls" -ge 3 ] && [ "${sleeps:-0}" -ge 2 ]
) && _record "429 x3: exit 5, retries attempted, sleeps invoked" 0 \
  || _record "429 x3: exit 5, retries attempted, sleeps invoked" 1

# --- secret handling -------------------------------------------------------

printf '== secret handling ==\n'

(
  _scenario argv-leak
  _run_single_call 200 "$REPO_ROOT/test/fixtures/api/2xx.json" GET /projects/
  ec=$?
  # API key must never appear in any curl argv log.
  if [ "$ec" -eq 0 ] && ! grep -q "$PLANE_API_KEY" "$PLANE_TEST_TMP"/curl-argv-*.log 2>/dev/null; then
    exit 0
  fi
  exit 1
) && _record "API key never in argv logs" 0 || _record "API key never in argv logs" 1

(
  _scenario stdin-has-key
  _run_single_call 200 "$REPO_ROOT/test/fixtures/api/2xx.json" GET /projects/
  # The key should be present exactly once: in the curl stdin config (--config -).
  if grep -q "$PLANE_API_KEY" "$PLANE_TEST_TMP"/curl-stdin-*.log 2>/dev/null; then
    exit 0
  fi
  exit 1
) && _record "API key passed via stdin config (--config -)" 0 \
  || _record "API key passed via stdin config (--config -)" 1

(
  _scenario env-unset-for-child
  _run_single_call 200 "$REPO_ROOT/test/fixtures/api/2xx.json" GET /projects/
  # mock_curl captured env filtered to PLANE_* and API_KEY. The named env var
  # (PLANE_API_KEY) must NOT appear in the env log — env -u stripped it.
  if ! grep -q "^PLANE_API_KEY=" "$PLANE_TEST_TMP"/curl-env-*.log 2>/dev/null; then
    exit 0
  fi
  exit 1
) && _record "named key env unset in curl child (env -u)" 0 \
  || _record "named key env unset in curl child (env -u)" 1

# --- redaction -------------------------------------------------------------

printf '== redaction ==\n'

(
  _scenario redact-keys
  out=$(_core_redact "$REPO_ROOT/test/fixtures/api/redact-body.json" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"api_key":"<redacted>"' \
     && printf '%s' "$out" | grep -q '"token":"<redacted>"' \
     && printf '%s' "$out" | grep -q '"Authorization":"<redacted>"' \
     && printf '%s' "$out" | grep -q '"name":"ok"'; then
    exit 0
  fi
  exit 1
) && _record "redact: keys masked, non-sensitive intact" 0 \
  || _record "redact: keys masked, non-sensitive intact" 1

(
  _scenario redact-truncate
  big="$PLANE_TEST_TMP/big.json"
  # Build a body > 2048 bytes.
  printf '{"data":"' > "$big"
  # 2500 characters of 'x'
  i=0; while [ "$i" -lt 50 ]; do printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' >> "$big"; i=$((i+1)); done
  printf '"}\n' >> "$big"
  out=$(_core_redact "$big" 2>/dev/null)
  out_len=$(printf '%s' "$out" | wc -c | tr -d ' ')
  if [ "$out_len" -le 2200 ] && printf '%s' "$out" | grep -q 'truncated'; then
    exit 0
  fi
  exit 1
) && _record "redact: bodies > 2KB truncated" 0 \
  || _record "redact: bodies > 2KB truncated" 1

# --- temp-file cleanup -----------------------------------------------------

printf '== tmp-file cleanup ==\n'

(
  _scenario tmp-cleanup
  # Register a few fake tmp files, then trigger cleanup.
  a=$(mktemp "$PLANE_TEST_TMP/plane-XXXX")
  b=$(mktemp "$PLANE_TEST_TMP/plane-XXXX")
  _core_register_tmp "$a"
  _core_register_tmp "$b"
  _core_cleanup_tmps
  if [ ! -e "$a" ] && [ ! -e "$b" ]; then
    exit 0
  fi
  exit 1
) && _record "_core_cleanup_tmps removes registered files" 0 \
  || _record "_core_cleanup_tmps removes registered files" 1

# --- preflight cache -------------------------------------------------------

printf '== preflight cache ==\n'

(
  _scenario preflight-cache
  counter="$PLANE_TEST_TMP/preflight-calls"
  : > "$counter"
  # Shadow the real preflight body with one that bumps the counter.
  _core_preflight_check() { printf 'x' >> "$counter"; return 0; }
  _core_preflight
  _core_preflight
  n=$(wc -c < "$counter" | tr -d ' ')
  [ "$n" = "1" ]
) && _record "_core_preflight runs check exactly once per process" 0 \
  || _record "_core_preflight runs check exactly once per process" 1

# --- summary ---------------------------------------------------------------

printf '\n== _core.test.sh summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'failures:%s\n' "$failures" >&2
  exit 1
fi
exit 0
