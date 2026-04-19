#!/usr/bin/env bash
# test/_resource.test.sh — unit-level checks for the _resource helpers.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
export PLANE_LIB_DIR="$REPO_ROOT/lib"
# shellcheck source=../lib/_parse.sh
. "$REPO_ROOT/lib/_parse.sh"
# shellcheck source=../lib/_core.sh
. "$REPO_ROOT/lib/_core.sh"
# shellcheck source=../lib/_endpoint_map.sh
. "$REPO_ROOT/lib/_endpoint_map.sh"
# shellcheck source=../lib/_resource.sh
. "$REPO_ROOT/lib/_resource.sh"

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

# --- is_destructive --------------------------------------------------------
printf '== destructive classification ==\n'
_resource_is_destructive projects delete && _record "projects.delete is destructive" 0 || _record "projects.delete is destructive" 1
_resource_is_destructive projects list   && _record "projects.list is NOT destructive" 1 || _record "projects.list is NOT destructive" 0
_resource_is_destructive cycles archive  && _record "cycles.archive is destructive" 0 || _record "cycles.archive is destructive" 1
_resource_is_destructive cycles transfer-work-items && _record "cycles.transfer-work-items is destructive" 0 || _record "cycles.transfer-work-items is destructive" 1
_resource_is_destructive issues create   && _record "issues.create is NOT destructive" 1 || _record "issues.create is NOT destructive" 0
_resource_is_destructive time-entries delete && _record "time-entries.delete is destructive" 0 || _record "time-entries.delete is destructive" 1

# --- endpoint lookup -------------------------------------------------------
printf '== endpoint lookup ==\n'
val=$(_resource_endpoint projects.list)
[ "$val" = "GET /projects/" ] \
  && _record "_resource_endpoint projects.list" 0 \
  || _record "_resource_endpoint projects.list" 1 "got: $val"

( _resource_endpoint nosuch.action >/dev/null 2>&1 )
ec=$?
[ "$ec" -eq 3 ] \
  && _record "_resource_endpoint unknown -> exit 3" 0 \
  || _record "_resource_endpoint unknown -> exit 3" 1 "exit=$ec"

# --- interpolation ---------------------------------------------------------
printf '== interpolation ==\n'
out=$(_resource_expand '/projects/${project_id}/issues/${issue_id}/' project_id=abc issue_id=xyz)
if [ "$out" = "/projects/abc/issues/xyz/" ]; then
  _record "_resource_expand substitutes placeholders" 0
else
  _record "_resource_expand substitutes placeholders" 1 "got: $out"
fi

out=$(_resource_expand '/projects/${project_id}/' project_id=)
if [ "$out" = "/projects//" ]; then
  _record "_resource_expand handles empty value" 0
else
  _record "_resource_expand handles empty value" 1 "got: $out"
fi

# --- dry-run transcript ----------------------------------------------------
printf '== dry-run transcript ==\n'
out=$( ( _resource_dryrun DELETE https://x.test/projects/abc/ ) 2>&1 )
ec=$?
if [ "$ec" -eq 7 ] \
   && printf '%s' "$out" | grep -q 'dry-run: DELETE' \
   && printf '%s' "$out" | grep -q 'destructive verb'; then
  _record "_resource_dryrun returns 7 with transcript" 0
else
  _record "_resource_dryrun returns 7 with transcript" 1 "exit=$ec out=$out"
fi

# Body redaction in dry-run
body=$(mktemp "${TMPDIR:-/tmp}/plane-dryrun-body.XXXXXX")
printf '{"api_key":"leak","name":"ok"}\n' > "$body"
out=$( ( _resource_dryrun POST https://x.test/foo/ "$body" ) 2>&1 )
if printf '%s' "$out" | grep -q '"api_key":"<redacted>"' \
   && printf '%s' "$out" | grep -q '"name":"ok"'; then
  _record "dry-run body redaction masks secrets" 0
else
  _record "dry-run body redaction masks secrets" 1 "$out"
fi
rm -f "$body"

# --- JSON vs pretty routing ------------------------------------------------
printf '== output routing ==\n'
(
  unset PLANE_FORCE_JSON PLANE_FORCE_PRETTY
  export PLANE_FORCE_JSON=1
  _resource_want_json && exit 0 || exit 1
) && _record "want_json honors PLANE_FORCE_JSON=1" 0 \
  || _record "want_json honors PLANE_FORCE_JSON=1" 1

(
  unset PLANE_FORCE_JSON
  export PLANE_FORCE_PRETTY=1
  _resource_want_json && exit 1 || exit 0
) && _record "want_json honors PLANE_FORCE_PRETTY=1" 0 \
  || _record "want_json honors PLANE_FORCE_PRETTY=1" 1

# --- _resource_parse_data_arg ---------------------------------------------
printf '== data arg parsing ==\n'

path=$(_resource_parse_data_arg '{"name":"ok"}')
if [ -f "$path" ] && jq -e '.name == "ok"' "$path" >/dev/null 2>&1; then
  _record "inline JSON -> tmp file with valid contents" 0
else
  _record "inline JSON -> tmp file with valid contents" 1
fi

src=$(mktemp "${TMPDIR:-/tmp}/plane-src.XXXXXX")
printf '{"payload":"file"}\n' > "$src"
path=$(_resource_parse_data_arg "@$src")
if [ -f "$path" ] && jq -e '.payload == "file"' "$path" >/dev/null 2>&1; then
  _record "@file JSON -> copies and validates" 0
else
  _record "@file JSON -> copies and validates" 1
fi
rm -f "$src"

( _resource_parse_data_arg '{"invalid":' >/dev/null 2>&1 )
ec=$?
[ "$ec" -eq 2 ] && _record "invalid JSON -> exit 2" 0 || _record "invalid JSON -> exit 2" 1 "exit=$ec"

( _resource_parse_data_arg '@/does/not/exist' >/dev/null 2>&1 )
ec=$?
[ "$ec" -eq 2 ] && _record "@missing-file -> exit 2" 0 || _record "@missing-file -> exit 2" 1 "exit=$ec"

printf '\n== _resource.test.sh summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
[ "$fail" -gt 0 ] && { printf 'failures:%s\n' "$failures" >&2; exit 1; }
exit 0
