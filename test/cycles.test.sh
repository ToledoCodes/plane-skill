#!/usr/bin/env bash
# test/cycles.test.sh — covers core CRUD + bespoke cycle-issues / transfer actions.
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
  "$PLANE" cycles list --project P-1 >/dev/null 2>&1
  grep -q '/projects/P-1/cycles/' "$SDIR"/curl-argv-*.log
) && _record "cycles list hits /projects/P-1/cycles/" 0 || _record "cycles list hits /projects/P-1/cycles/" 1

# Archive is destructive.
(
  _sandbox archive-dryrun
  "$PLANE" cycles archive --project P-1 C-1 >/dev/null 2>&1
  [ $? -eq 7 ]
) && _record "cycles archive (no --execute) -> dry-run exit 7" 0 || _record "cycles archive (no --execute) -> dry-run exit 7" 1

# Bespoke: add-work-items POSTs with JSON array
(
  _sandbox add-work-items
  export MOCK_CURL_STATUS=201 MOCK_CURL_BODY="$REPO_ROOT/test/fixtures/api/2xx.json" MOCK_CURL_HEADERS="$REPO_ROOT/test/fixtures/api/ok-headers.txt"
  "$PLANE" cycles add-work-items --project P-1 C-1 --issues I-1,I-2,I-3 >/dev/null 2>&1
  ec=$?
  grep -q 'POST' "$SDIR"/curl-argv-*.log \
    && grep -q '/projects/P-1/cycles/C-1/cycle-issues/' "$SDIR"/curl-argv-*.log \
    && [ "$ec" -eq 0 ]
) && _record "cycles add-work-items -> POST /cycles/C-1/cycle-issues/" 0 \
  || _record "cycles add-work-items -> POST /cycles/C-1/cycle-issues/" 1

# Bespoke: remove-work-item DELETEs and is destructive -> dry-run
(
  _sandbox remove-dryrun
  "$PLANE" cycles remove-work-item --project P-1 C-1 I-1 >/dev/null 2>&1
  [ $? -eq 7 ]
) && _record "cycles remove-work-item (no --execute) -> dry-run" 0 \
  || _record "cycles remove-work-item (no --execute) -> dry-run" 1

# Bespoke: transfer-work-items is destructive -> dry-run
(
  _sandbox transfer-dryrun
  "$PLANE" cycles transfer-work-items --project P-1 C-1 --target C-2 >/dev/null 2>&1
  [ $? -eq 7 ]
) && _record "cycles transfer-work-items (no --execute) -> dry-run" 0 \
  || _record "cycles transfer-work-items (no --execute) -> dry-run" 1

printf '\n== cycles.test.sh ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
[ "$fail" -gt 0 ] && { printf 'failures:%s\n' "$failures" >&2; exit 1; }
exit 0
