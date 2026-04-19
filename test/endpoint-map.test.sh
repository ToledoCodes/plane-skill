#!/usr/bin/env bash
# test/endpoint-map.test.sh — structural checks over lib/_endpoint_map.sh.
#
# We don't probe the network here — Unit 3 probes are recorded in
# docs/premise-validation.md. These assertions protect against regressions
# in the hand-authored map shape and coverage.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
# shellcheck source=../lib/_endpoint_map.sh
. "$REPO_ROOT/lib/_endpoint_map.sh"

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

# 1. Minimum count.
n=${#PLANE_ENDPOINTS[@]}
if [ "$n" -ge 40 ]; then
  _record "entry count >= 40 (got $n)" 0
else
  _record "entry count >= 40 (got $n)" 1 "expected >= 40"
fi

# 2. Every value matches "^(GET|POST|PUT|PATCH|DELETE) /.+/$".
bad_values=""
for key in "${!PLANE_ENDPOINTS[@]}"; do
  val="${PLANE_ENDPOINTS[$key]}"
  case "$val" in
    'GET /'*/|'POST /'*/|'PUT /'*/|'PATCH /'*/|'DELETE /'*/) : ;;
    *) bad_values="${bad_values}
    $key -> $val" ;;
  esac
done
if [ -z "$bad_values" ]; then
  _record "all values match METHOD /path/ shape" 0
else
  _record "all values match METHOD /path/ shape" 1 "$bad_values"
fi

# 3. All 7 T1 resources expose list/get/create/update/delete.
missing=""
for resource in projects issues cycles labels states comments time-entries; do
  for action in list get create update delete; do
    key="${resource}.${action}"
    if [ -z "${PLANE_ENDPOINTS[$key]:-}" ]; then
      missing="${missing}
    $key"
    fi
  done
done
if [ -z "$missing" ]; then
  _record "every T1 resource has list/get/create/update/delete" 0
else
  _record "every T1 resource has list/get/create/update/delete" 1 "$missing"
fi

# 4. Resource-specific actions called out by the plan exist.
expected_extras=(
  "projects.archive"
  "projects.unarchive"
  "issues.resolve"
  "cycles.archive"
  "cycles.add-work-items"
  "cycles.remove-work-item"
  "cycles.transfer-work-items"
  "cycles.list-work-items"
  "time-entries.list-workspace"
)
missing_extras=""
for key in "${expected_extras[@]}"; do
  [ -z "${PLANE_ENDPOINTS[$key]:-}" ] && missing_extras="${missing_extras}
    $key"
done
if [ -z "$missing_extras" ]; then
  _record "plan-specific extra actions present" 0
else
  _record "plan-specific extra actions present" 1 "$missing_extras"
fi

# 5. No key contains whitespace or unexpected characters.
bad_keys=""
for key in "${!PLANE_ENDPOINTS[@]}"; do
  case "$key" in
    *.*) : ;;
    *) bad_keys="${bad_keys}
    $key (missing .action)" ;;
  esac
  case "$key" in
    *[[:space:]]*) bad_keys="${bad_keys}
    $key (whitespace)" ;;
  esac
done
if [ -z "$bad_keys" ]; then
  _record "all keys use resource.action shape, no whitespace" 0
else
  _record "all keys use resource.action shape, no whitespace" 1 "$bad_keys"
fi

# 6. Source guard: sourcing twice does not double-populate.
prev_count=${#PLANE_ENDPOINTS[@]}
# shellcheck source=../lib/_endpoint_map.sh
. "$REPO_ROOT/lib/_endpoint_map.sh"
if [ "${#PLANE_ENDPOINTS[@]}" -eq "$prev_count" ]; then
  _record "source guard prevents re-population" 0
else
  _record "source guard prevents re-population" 1 \
    "count went from $prev_count -> ${#PLANE_ENDPOINTS[@]}"
fi

printf '\n== endpoint-map.test.sh summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'failures:%s\n' "$failures" >&2
  exit 1
fi
exit 0
