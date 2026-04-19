#!/usr/bin/env bash
# test/lib/mock_curl.sh — PATH-shim curl mock for the plane test suite.
#
# Contract with tests:
#   PLANE_TEST_TMP           — required; dir where argv/stdin/env logs are written.
#   MOCK_CURL_SCRIPT         — optional path to a script that picks behavior
#                              per-call (for multi-call scenarios, e.g. 500→200
#                              retry). The script receives the call index in $1
#                              and must echo one of:
#                                STATUS=<code> BODY=<path> [HEADERS=<path>] [EXIT=<n>]
#                              on stdout. If unset, the single-shot env vars
#                              below apply every call.
#   MOCK_CURL_STATUS         — HTTP status to emit when no script (default 200).
#   MOCK_CURL_BODY           — path to a fixture body file to emit when no script.
#   MOCK_CURL_HEADERS        — path to a fixture response-header file (optional).
#   MOCK_CURL_EXIT           — curl-style exit code to return (default 0).
#                              Non-zero means transport error (6/7/28/35/56/60…).
#
# What the mock captures:
#   $PLANE_TEST_TMP/curl-argv-<N>.log   — full argv of each call (newline-delim).
#   $PLANE_TEST_TMP/curl-stdin-<N>.log  — everything read from stdin (curl --config -).
#   $PLANE_TEST_TMP/curl-env-<N>.log    — env at call time (filtered to PLANE_*).
#   $PLANE_TEST_TMP/curl-calls          — integer count of calls made.
#
# What the mock emits:
#   stdout  — contents of the selected body fixture (may be empty).
#   stderr  — nothing (real curl is called with -sS).
#   stderr (via -D <file>) — the selected headers fixture is copied to -D path.
#   The last line on stdout is the HTTP status, matching the real `-w '%{http_code}'`
#   pattern used by _core_http.
set -u

if [ -z "${PLANE_TEST_TMP:-}" ]; then
  printf 'mock_curl: PLANE_TEST_TMP is unset; cannot record call\n' >&2
  exit 64
fi
mkdir -p "$PLANE_TEST_TMP"

# Atomic call-counter increment (portable, no flock).
calls_file="$PLANE_TEST_TMP/curl-calls"
[ -f "$calls_file" ] || printf '0\n' > "$calls_file"
prev=$(cat "$calls_file")
idx=$((prev + 1))
printf '%d\n' "$idx" > "$calls_file"

# Persist argv + env for assertions.
argv_log="$PLANE_TEST_TMP/curl-argv-$idx.log"
env_log="$PLANE_TEST_TMP/curl-env-$idx.log"
stdin_log="$PLANE_TEST_TMP/curl-stdin-$idx.log"
: > "$argv_log"
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$argv_log"
done
env | grep -E '^(PLANE_|MOCK_CURL_|API_KEY=|X_API_KEY=|PATH=)' > "$env_log" || true

# Scan for -D <file> so we can write the fake response headers to it,
# matching curl's real behavior.
dest_headers=""
prev_arg=""
for arg in "$@"; do
  if [ "$prev_arg" = "-D" ] || [ "$prev_arg" = "--dump-header" ]; then
    dest_headers="$arg"
  fi
  prev_arg="$arg"
done

# Scan for -o <file> so we know where the body goes. _core_http always uses -o,
# so write the body there when present; otherwise emit on stdout.
dest_body=""
prev_arg=""
for arg in "$@"; do
  if [ "$prev_arg" = "-o" ] || [ "$prev_arg" = "--output" ]; then
    dest_body="$arg"
  fi
  prev_arg="$arg"
done

# Read stdin (curl --config - pattern) so tests can assert the header format.
if [ ! -t 0 ]; then
  cat > "$stdin_log" || true
else
  : > "$stdin_log"
fi

# Pick behavior. Script wins; otherwise env vars.
status="${MOCK_CURL_STATUS:-200}"
body_src="${MOCK_CURL_BODY:-}"
hdrs_src="${MOCK_CURL_HEADERS:-}"
exit_code="${MOCK_CURL_EXIT:-0}"

if [ -n "${MOCK_CURL_SCRIPT:-}" ] && [ -x "$MOCK_CURL_SCRIPT" ]; then
  decision=$("$MOCK_CURL_SCRIPT" "$idx")
  # Parse KEY=VALUE tokens from the decision line.
  for tok in $decision; do
    key=${tok%%=*}
    val=${tok#*=}
    case "$key" in
      STATUS)   status="$val" ;;
      BODY)     body_src="$val" ;;
      HEADERS)  hdrs_src="$val" ;;
      EXIT)     exit_code="$val" ;;
    esac
  done
fi

# If EXIT != 0, simulate a curl transport error: emit nothing, return the code.
if [ "$exit_code" != "0" ]; then
  exit "$exit_code"
fi

# Write body to -o dest (or stdout if none).
if [ -n "$body_src" ] && [ -f "$body_src" ]; then
  if [ -n "$dest_body" ]; then
    cat "$body_src" > "$dest_body"
  else
    cat "$body_src"
  fi
elif [ -n "$dest_body" ]; then
  : > "$dest_body"
fi

# Write headers to -D dest if both given.
if [ -n "$hdrs_src" ] && [ -f "$hdrs_src" ] && [ -n "$dest_headers" ]; then
  cat "$hdrs_src" > "$dest_headers"
elif [ -n "$dest_headers" ]; then
  # Always leave a minimal header line so downstream parsing doesn't trip.
  printf 'HTTP/1.1 %s\r\n\r\n' "$status" > "$dest_headers"
fi

# Emit the HTTP status on stdout so -w '%{http_code}' behavior works.
# When -o is set (normal path), stdout is only the status.
if [ -n "$dest_body" ]; then
  printf '%s' "$status"
else
  printf '%s' "$status"
fi

exit 0
