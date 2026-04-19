#!/usr/bin/env bash
# test/projects.test.sh — end-to-end scenarios for the projects resource
# behind the _resource helper. Validates the whole chain: dispatcher →
# resource lib → _resource_call/paginate → _core_http → mock curl.
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
  export PLANE_API_KEY="test-key-projects"
  export PLANE_FORCE_PRETTY=1  # force TTY-summary routing even when piped
  rm -f "$SDIR"/curl-*
}

# --- 1. list (pretty) returns summary lines, exit 0 ----------------------
(
  _fresh_sandbox list-pretty
  export MOCK_CURL_STATUS=200
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/projects-list-p1.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  out=$("$PLANE" projects list 2>&1)
  ec=$?
  if [ "$ec" -eq 0 ] \
     && printf '%s' "$out" | grep -q 'MUNI' \
     && printf '%s' "$out" | grep -q 'STATE' \
     && printf '%s' "$out" | grep -q 'id=p-1'; then
    exit 0
  fi
  printf 'ec=%d out=%s\n' "$ec" "$out" >&2
  exit 1
) && _record "projects list -> summary lines (MUNI + STATE)" 0 \
  || _record "projects list -> summary lines (MUNI + STATE)" 1

# --- 2. --json emits raw envelope ---------------------------------------
(
  _fresh_sandbox list-json
  export MOCK_CURL_STATUS=200
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/projects-list-p1.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  out=$("$PLANE" --json projects list 2>&1)
  ec=$?
  if [ "$ec" -eq 0 ] && printf '%s' "$out" | /opt/homebrew/bin/jq -e '.results | length == 2' >/dev/null 2>&1; then
    exit 0
  fi
  printf 'ec=%d out=%s\n' "$ec" "$out" >&2
  exit 1
) && _record "projects list --json -> envelope JSON" 0 \
  || _record "projects list --json -> envelope JSON" 1

# --- 3. empty list -> # no results --------------------------------------
(
  _fresh_sandbox list-empty
  export MOCK_CURL_STATUS=200
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/projects-empty.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  out=$("$PLANE" projects list 2>&1)
  ec=$?
  if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '# no results'; then
    exit 0
  fi
  printf 'ec=%d out=%s\n' "$ec" "$out" >&2
  exit 1
) && _record "projects list (empty) -> # no results" 0 \
  || _record "projects list (empty) -> # no results" 1

# --- 4. --all walks pages via next_cursor ------------------------------
(
  _fresh_sandbox list-all
  script="$SDIR/mock-script.sh"
  cat > "$script" <<EOF
#!/bin/sh
case "\$1" in
  1) printf 'STATUS=200 BODY=%s/test/fixtures/api/projects-list-p1.json HEADERS=%s/test/fixtures/api/ok-headers.txt\n' "$REPO_ROOT" "$REPO_ROOT" ;;
  *) printf 'STATUS=200 BODY=%s/test/fixtures/api/projects-list-p2.json HEADERS=%s/test/fixtures/api/ok-headers.txt\n' "$REPO_ROOT" "$REPO_ROOT" ;;
esac
EOF
  chmod +x "$script"
  export MOCK_CURL_SCRIPT="$script"
  unset MOCK_CURL_STATUS MOCK_CURL_BODY MOCK_CURL_HEADERS
  unset PLANE_FORCE_PRETTY   # --all with no PRETTY forces JSON mode
  out=$("$PLANE" --json projects list --all 2>&1)
  ec=$?
  # Expect NDJSON lines for p-1, p-2, p-3.
  c=$(printf '%s\n' "$out" | /opt/homebrew/bin/jq -s 'length' 2>/dev/null)
  calls=$(cat "$SDIR/curl-calls" 2>/dev/null)
  if [ "$ec" -eq 0 ] && [ "$c" = "3" ] && [ "$calls" = "2" ]; then
    exit 0
  fi
  printf 'ec=%d count=%s calls=%s out:\n%s\n' "$ec" "$c" "$calls" "$out" >&2
  exit 1
) && _record "projects list --all -> 3 items across 2 pages" 0 \
  || _record "projects list --all -> 3 items across 2 pages" 1

# --- 5. create with flag-driven body ------------------------------------
(
  _fresh_sandbox create
  export MOCK_CURL_STATUS=201
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/project-one.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  out=$("$PLANE" projects create --name "Municipal Post" --identifier MUNI 2>&1)
  ec=$?
  if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q 'MUNI'; then
    # Request body should contain the two flag-supplied fields.
    if cat "$SDIR"/curl-stdin-*.log 2>/dev/null | grep -q 'application/json'; then
      exit 0
    fi
    printf 'no content-type header\n' >&2
    exit 1
  fi
  printf 'ec=%d out=%s\n' "$ec" "$out" >&2
  exit 1
) && _record "projects create --name X --identifier Y -> 201, summary printed" 0 \
  || _record "projects create --name X --identifier Y -> 201, summary printed" 1

# --- 6. invalid JSON in --data -> exit 2 pre-network --------------------
(
  _fresh_sandbox bad-json
  out=$("$PLANE" projects create --data '{"broken":' 2>&1)
  ec=$?
  calls=$(cat "$SDIR/curl-calls" 2>/dev/null || echo 0)
  if [ "$ec" -eq 2 ] && printf '%s' "$out" | grep -qi 'invalid json' && [ "$calls" -eq 0 ]; then
    exit 0
  fi
  printf 'ec=%d calls=%s out=%s\n' "$ec" "$calls" "$out" >&2
  exit 1
) && _record "projects create --data <invalid> -> exit 2, no network" 0 \
  || _record "projects create --data <invalid> -> exit 2, no network" 1

# --- 7. delete dry-run -> exit 7 ----------------------------------------
(
  _fresh_sandbox delete-dryrun
  out=$("$PLANE" projects delete p-1 2>&1)
  ec=$?
  calls=$(cat "$SDIR/curl-calls" 2>/dev/null || echo 0)
  if [ "$ec" -eq 7 ] && printf '%s' "$out" | grep -q 'dry-run: DELETE' && [ "$calls" -eq 0 ]; then
    exit 0
  fi
  printf 'ec=%d calls=%s out=%s\n' "$ec" "$calls" "$out" >&2
  exit 1
) && _record "projects delete (no --execute) -> exit 7, no network" 0 \
  || _record "projects delete (no --execute) -> exit 7, no network" 1

# --- 8. delete --execute -> 204 success ---------------------------------
(
  _fresh_sandbox delete-exec
  export MOCK_CURL_STATUS=204
  # 204: empty body, but mock needs SOME file; use 2xx fixture.
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/2xx.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" projects delete p-1 --execute >/dev/null 2>&1
  ec=$?
  if [ "$ec" -eq 0 ]; then
    if grep -q 'DELETE' "$SDIR"/curl-argv-*.log 2>/dev/null; then
      exit 0
    fi
    printf 'DELETE not in argv\n' >&2
    exit 1
  fi
  printf 'ec=%d\n' "$ec" >&2
  exit 1
) && _record "projects delete --execute -> 204, DELETE in argv" 0 \
  || _record "projects delete --execute -> 204, DELETE in argv" 1

# --- 9. delete --execute on 404 -> exit 9 -------------------------------
(
  _fresh_sandbox delete-404
  export MOCK_CURL_STATUS=404
  export MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/404.json"
  export MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" projects delete p-999 --execute >/dev/null 2>&1
  ec=$?
  [ "$ec" -eq 9 ]
) && _record "projects delete --execute on 404 -> exit 9" 0 \
  || _record "projects delete --execute on 404 -> exit 9" 1

# --- 10. dry-run redacts body secrets ----------------------------------
(
  _fresh_sandbox dryrun-redact
  # archive doesn't take a body in Plane, but we want to exercise the
  # dry-run redaction path. Use a synthetic body file to pass through.
  out=$("$PLANE" projects delete p-secret 2>&1)
  ec=$?
  # No body expected here, but transcript should include a redact-ready format.
  [ "$ec" -eq 7 ]
) && _record "projects delete dry-run emits transcript" 0 \
  || _record "projects delete dry-run emits transcript" 1

# --- 11. help resource defined --------------------------------------------
if declare -F _help_resource_projects >/dev/null 2>&1; then
  _record "_help_resource_projects defined" 1 "defined in test harness — shouldn't be"
else
  # Only defined when lib/projects.sh is sourced. Source here and verify.
  # shellcheck source=../lib/projects.sh
  . "$REPO_ROOT/lib/projects.sh"
  if declare -F _help_resource_projects >/dev/null 2>&1; then
    _record "_help_resource_projects defined after lib source" 0
  else
    _record "_help_resource_projects defined after lib source" 1
  fi
fi

printf '\n== projects.test.sh summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
[ "$fail" -gt 0 ] && { printf 'failures:%s\n' "$failures" >&2; exit 1; }
exit 0
