#!/usr/bin/env bash
# test/version.test.sh — `plane version` works offline, no config, exit 0.
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

# 1. `plane version` exits 0 with no config file in sight.
unset PLANE_API_KEY PLANE_WORKSPACE_SLUG PLANE_API_URL
export PLANE_CONFIG_PATH="$PLANE_TEST_TMP/does-not-exist"
out=$("$PLANE" version 2>&1)
ec=$?
if [ "$ec" -eq 0 ]; then
  _record "plane version exits 0 offline, no config" 0
else
  _record "plane version exits 0 offline, no config" 1 "exit=$ec out=$out"
fi

# 2. `plane --version` behaves identically.
out2=$("$PLANE" --version 2>&1)
ec2=$?
if [ "$ec2" -eq 0 ] && [ "$out" = "$out2" ]; then
  _record "plane --version matches plane version" 0
else
  _record "plane --version matches plane version" 1 "exit=$ec2"
fi

# 3. Output mentions bash, curl, jq.
if printf '%s' "$out" | grep -q 'bash:' \
   && printf '%s' "$out" | grep -q 'curl:' \
   && printf '%s' "$out" | grep -q 'jq:'; then
  _record "version output includes bash/curl/jq lines" 0
else
  _record "version output includes bash/curl/jq lines" 1 "$out"
fi

# 4. Spec line is present (even if "none").
if printf '%s' "$out" | grep -q '^  spec:'; then
  _record "version output includes spec: line" 0
else
  _record "version output includes spec: line" 1 "$out"
fi

# 5. `plane version` must NOT issue any curl call.
calls_before=$(cat "$PLANE_TEST_TMP/curl-calls" 2>/dev/null || echo 0)
"$PLANE" version >/dev/null 2>&1
calls_after=$(cat "$PLANE_TEST_TMP/curl-calls" 2>/dev/null || echo 0)
if [ "$calls_before" = "$calls_after" ]; then
  _record "plane version makes no network calls" 0
else
  _record "plane version makes no network calls" 1 \
    "curl invocation counter moved $calls_before -> $calls_after"
fi

printf '\n== version.test.sh summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
[ "$fail" -gt 0 ] && { printf 'failures:%s\n' "$failures" >&2; exit 1; }
exit 0
