#!/usr/bin/env bash
# test/doctor.test.sh — plane doctor exit codes across failure modes.
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

# Per-scenario sandbox dir that's unique per assertion. Centralises common
# config setup.
_fresh_sandbox() {
  # $1 = scenario name (used as subdir of PLANE_TEST_TMP so curl logs are
  # isolated per scenario).
  SDIR="$PLANE_TEST_TMP/$1"
  mkdir -p "$SDIR"
  export PLANE_TEST_TMP_ORIGIN="$PLANE_TEST_TMP"
  export PLANE_TEST_TMP="$SDIR"
  export PLANE_CONFIG_PATH="$SDIR/plane"
  cat > "$PLANE_CONFIG_PATH" <<EOF
workspace_slug=testws
api_url=https://example.test
api_key_env=PLANE_API_KEY
EOF
  chmod 600 "$PLANE_CONFIG_PATH"
  export PLANE_API_KEY="test-key-doctor"
  # Reset the mock counters + logs.
  rm -f "$SDIR"/curl-*
}

# --- Scenario 1: all checks pass (mocked 200 to /members/me/) -----------
(
  _fresh_sandbox doctor-happy
  export MOCK_CURL_STATUS=200
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/2xx.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  out=$("$PLANE" doctor 2>&1)
  ec=$?
  pass_count=$(printf '%s' "$out" | /usr/bin/grep -c '^PASS:')
  fail_count=$(printf '%s' "$out" | /usr/bin/grep -c '^FAIL:')
  [ "$ec" -eq 0 ] && [ "$pass_count" -eq 8 ] && [ "$fail_count" -eq 0 ]
) && _record "all 8 checks pass -> exit 0, 8 PASS / 0 FAIL" 0 \
  || _record "all 8 checks pass -> exit 0, 8 PASS / 0 FAIL" 1

# --- Scenario 2: missing jq -> FAIL check 2, exit 3 ---------------------
(
  _fresh_sandbox doctor-no-jq
  # Strip jq from PATH but keep curl mock + other tools.
  narrow_bin="$SDIR/bin-narrow"
  mkdir -p "$narrow_bin"
  ln -s "$REPO_ROOT/test/lib/mock_curl.sh" "$narrow_bin/curl"
  # Use a bash >= 4 so the dispatcher's bash-4 gate passes. On macOS the
  # Homebrew bash is canonical; fall back to /bin/bash (3.2) only if nothing
  # else is around — the scenario will still exercise the jq-missing branch,
  # but on bash 3.2 the gate fires first and masks the check.
  if [ -x /opt/homebrew/bin/bash ]; then
    ln -s /opt/homebrew/bin/bash "$narrow_bin/bash"
  elif [ -x /usr/local/bin/bash ]; then
    ln -s /usr/local/bin/bash "$narrow_bin/bash"
  else
    ln -s /bin/bash "$narrow_bin/bash"
  fi
  ln -s /usr/bin/env "$narrow_bin/env"
  ln -s /usr/bin/stat "$narrow_bin/stat"
  ln -s /usr/bin/printenv "$narrow_bin/printenv"
  ln -s /usr/bin/sed "$narrow_bin/sed"
  ln -s /usr/bin/awk "$narrow_bin/awk"
  ln -s /usr/bin/grep "$narrow_bin/grep"
  ln -s /usr/bin/tr "$narrow_bin/tr"
  ln -s /usr/bin/mktemp "$narrow_bin/mktemp"
  ln -s /bin/cat "$narrow_bin/cat"
  ln -s /usr/bin/basename "$narrow_bin/basename"
  ln -s /usr/bin/dirname "$narrow_bin/dirname"
  ln -s /usr/bin/head "$narrow_bin/head"
  export PATH="$narrow_bin"

  out=$("$PLANE" doctor 2>&1)
  ec=$?
  # Expected: "FAIL: jq present" shown, overall exit 3.
  if printf '%s' "$out" | /usr/bin/grep -q 'FAIL: jq' && [ "$ec" -eq 3 ]; then
    exit 0
  else
    printf 'ec=%d out=%s\n' "$ec" "$out" >&2
    exit 1
  fi
) && _record "missing jq -> FAIL jq, exit 3" 0 \
  || _record "missing jq -> FAIL jq, exit 3" 1

# --- Scenario 3: 401 connectivity -> FAIL check 8, exit 4 ---------------
(
  _fresh_sandbox doctor-401
  export MOCK_CURL_STATUS=401
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/401.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  out=$("$PLANE" doctor 2>&1)
  ec=$?
  # 7 of the first 7 checks should PASS (environment + config), only the
  # connectivity check fails.
  pass_count=$(printf '%s' "$out" | /usr/bin/grep -c '^PASS:')
  if [ "$ec" -eq 4 ] \
     && printf '%s' "$out" | /usr/bin/grep -q 'FAIL: connectivity' \
     && [ "$pass_count" -ge 6 ]; then
    exit 0
  else
    printf 'ec=%d pass_count=%d out=%s\n' "$ec" "$pass_count" "$out" >&2
    exit 1
  fi
) && _record "401 on connectivity -> FAIL check 8, exit 4" 0 \
  || _record "401 on connectivity -> FAIL check 8, exit 4" 1

# --- Scenario 4: transport failure -> exit 8 ----------------------------
(
  _fresh_sandbox doctor-transport
  export MOCK_CURL_EXIT=28   # curl "Operation timeout"
  export MOCK_CURL_STATUS=0
  out=$("$PLANE" doctor 2>&1)
  ec=$?
  if [ "$ec" -eq 8 ] \
     && printf '%s' "$out" | /usr/bin/grep -q 'FAIL: connectivity'; then
    exit 0
  else
    printf 'ec=%d out=%s\n' "$ec" "$out" >&2
    exit 1
  fi
) && _record "transport failure on connectivity -> exit 8" 0 \
  || _record "transport failure on connectivity -> exit 8" 1

printf '\n== doctor.test.sh summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
[ "$fail" -gt 0 ] && { printf 'failures:%s\n' "$failures" >&2; exit 1; }
exit 0
