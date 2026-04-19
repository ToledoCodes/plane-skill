#!/usr/bin/env bash
# test/install.test.sh — scenarios for install.sh + uninstall.sh from Unit 1.
#
# All scenarios redirect INSTALL_ROOT and CONFIG_PATH into a sandbox so the
# user's real ~/.claude is never touched. We run install.sh/uninstall.sh as
# subprocesses, assert exit codes and filesystem state, and tear down the
# sandbox between scenarios.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SANDBOX_BASE=$(mktemp -d "${TMPDIR:-/tmp}/plane-install-test.XXXXXX")
trap 'rm -rf "$SANDBOX_BASE"' EXIT INT TERM

pass=0
fail=0
failures=""

_record() {
  # _record <name> <exit> [<explanation>]
  local name="$1" exit_code="$2" why="${3:-}"
  if [ "$exit_code" -eq 0 ]; then
    pass=$((pass + 1))
    printf '  PASS %s\n' "$name"
  else
    fail=$((fail + 1))
    failures="${failures}
  $name"
    if [ -n "$why" ]; then
      failures="${failures}
    $why"
    fi
    printf '  FAIL %s\n' "$name" >&2
    [ -n "$why" ] && printf '    %s\n' "$why" >&2
  fi
}

# _sandbox <scenario_name>
# Creates per-scenario paths and ensures PLANE_API_KEY is set (install.sh
# doesn't care, but resource code will later).
_sandbox() {
  local name="$1"
  SB="$SANDBOX_BASE/$name"
  mkdir -p "$SB/home/.claude/skills" "$SB/home/.claude"
  export HOME="$SB/home"
  export PLANE_INSTALL_ROOT="$HOME/.claude/skills/plane"
  export PLANE_CONFIG_PATH="$HOME/.claude/.plane"
  # Tests run the real repo's install.sh against a sandbox HOME; the repo
  # itself sits outside that sandbox. Bypass the source-under-$HOME check
  # for scenarios that aren't specifically testing it.
  export PLANE_ALLOW_ANY_SOURCE=1
  # Default: provide a valid config so the preflight passes unless a scenario
  # wants to test the missing-config path.
  cat > "$PLANE_CONFIG_PATH" <<EOF
workspace_slug=testws
api_url=https://example.com
api_key_env=PLANE_API_KEY
EOF
  chmod 600 "$PLANE_CONFIG_PATH"
}

# Scenario 1: happy path, copy mode.
printf '== happy path: copy install ==\n'
_sandbox happy-copy
if bash "$REPO_ROOT/install.sh" >/dev/null 2>&1 \
   && [ -d "$PLANE_INSTALL_ROOT" ] \
   && [ -f "$PLANE_INSTALL_ROOT/bin/plane" ] \
   && [ -f "$PLANE_INSTALL_ROOT/install.sh" ]; then
  _record "install (copy) creates ~/.claude/skills/plane/ with bin/plane" 0
else
  _record "install (copy) creates ~/.claude/skills/plane/ with bin/plane" 1 "expected dir + bin/plane + install.sh not present"
fi

# Scenario 2: .install-sha recorded when repo is a git checkout.
if [ -d "$REPO_ROOT/.git" ]; then
  if [ -f "$PLANE_INSTALL_ROOT/.install-sha" ]; then
    sha=$(cat "$PLANE_INSTALL_ROOT/.install-sha")
    expected=$(cd "$REPO_ROOT" && git rev-parse HEAD)
    if [ "$sha" = "$expected" ]; then
      _record ".install-sha matches git HEAD" 0
    else
      _record ".install-sha matches git HEAD" 1 "recorded $sha, expected $expected"
    fi
  else
    _record ".install-sha matches git HEAD" 1 "no .install-sha written"
  fi
fi

# Scenario 3: idempotent second run.
printf '== edge: idempotent second run ==\n'
if bash "$REPO_ROOT/install.sh" >/dev/null 2>&1; then
  _record "second install is a no-op (exit 0)" 0
else
  _record "second install is a no-op (exit 0)" 1 "re-run exited non-zero"
fi

# Scenario 4: uninstall removes the dir.
printf '== happy path: uninstall ==\n'
if bash "$REPO_ROOT/uninstall.sh" >/dev/null 2>&1 \
   && [ ! -e "$PLANE_INSTALL_ROOT" ]; then
  _record "uninstall removes ~/.claude/skills/plane" 0
else
  _record "uninstall removes ~/.claude/skills/plane" 1 "dir still present"
fi

# Scenario 5: symlink mode.
printf '== happy path: symlink install ==\n'
_sandbox happy-symlink
if bash "$REPO_ROOT/install.sh" --symlink >/dev/null 2>&1 \
   && [ -L "$PLANE_INSTALL_ROOT" ]; then
  target=$(readlink "$PLANE_INSTALL_ROOT")
  if [ "$target" = "$REPO_ROOT" ]; then
    _record "symlink mode points to source repo" 0
  else
    _record "symlink mode points to source repo" 1 "link target=$target, expected=$REPO_ROOT"
  fi
else
  _record "symlink mode points to source repo" 1 "install did not create symlink"
fi

# Scenario 6: uninstall after symlink install.
if bash "$REPO_ROOT/uninstall.sh" >/dev/null 2>&1 \
   && [ ! -e "$PLANE_INSTALL_ROOT" ] \
   && [ ! -L "$PLANE_INSTALL_ROOT" ] \
   && [ -d "$REPO_ROOT" ]; then
  _record "uninstall removes symlink but not source repo" 0
else
  _record "uninstall removes symlink but not source repo" 1 "state after uninstall unexpected"
fi

# Scenario 7: missing config → exit 3 with cp hint.
printf '== error: missing ~/.claude/.plane ==\n'
_sandbox missing-config
rm -f "$PLANE_CONFIG_PATH"
out_file=$(mktemp "$SANDBOX_BASE/out.XXXXXX")
bash "$REPO_ROOT/install.sh" >"$out_file" 2>&1
ec=$?
if [ "$ec" -eq 3 ] && grep -q 'example-plane-config' "$out_file" \
   && [ ! -e "$PLANE_INSTALL_ROOT" ]; then
  _record "missing config → exit 3, prints cp hint, skill not installed" 0
else
  _record "missing config → exit 3, prints cp hint, skill not installed" 1 \
    "exit=$ec; output: $(cat "$out_file")"
fi

# Scenario 8: config mode broader than 0600 → warn, still proceed.
printf '== edge: config mode 0644 ==\n'
_sandbox perm-0644
chmod 644 "$PLANE_CONFIG_PATH"
out_file=$(mktemp "$SANDBOX_BASE/out.XXXXXX")
bash "$REPO_ROOT/install.sh" >"$out_file" 2>&1
ec=$?
if [ "$ec" -eq 0 ] && grep -qi 'recommend 0600\|warning' "$out_file"; then
  _record "0644 config → warning but install proceeds" 0
else
  _record "0644 config → warning but install proceeds" 1 \
    "exit=$ec; output: $(cat "$out_file")"
fi

# Scenario 9: source repo outside $HOME → refuse.
printf '== error: source repo outside $HOME ==\n'
_sandbox outside-home
# Create an alt "source" copy under /tmp (outside HOME).
alt_src="$SANDBOX_BASE/outside-home/outside-src"
mkdir -p "$alt_src"
cp -p "$REPO_ROOT/install.sh" "$alt_src/install.sh"
mkdir -p "$alt_src/docs"
cp -p "$REPO_ROOT/docs/example-plane-config" "$alt_src/docs/example-plane-config"
# Ensure the alt path is not under $HOME by unsetting HOME to a narrower tree.
export HOME="$SB/home-narrow"
mkdir -p "$HOME/.claude"
cp -p "$REPO_ROOT/docs/example-plane-config" "$HOME/.claude/.plane"
chmod 600 "$HOME/.claude/.plane"
export PLANE_INSTALL_ROOT="$HOME/.claude/skills/plane"
export PLANE_CONFIG_PATH="$HOME/.claude/.plane"
# This scenario specifically tests the source-under-$HOME gate, so clear the bypass.
unset PLANE_ALLOW_ANY_SOURCE
out_file=$(mktemp "$SANDBOX_BASE/out.XXXXXX")
bash "$alt_src/install.sh" >"$out_file" 2>&1
ec=$?
if [ "$ec" -eq 3 ] && grep -q 'must live under' "$out_file"; then
  _record "source outside \$HOME → exit 3, refuses" 0
else
  _record "source outside \$HOME → exit 3, refuses" 1 \
    "exit=$ec; output: $(cat "$out_file")"
fi

# Scenario 10: uninstall when install dir already absent → exit 0.
printf '== edge: uninstall when absent ==\n'
_sandbox uninstall-absent
out_file=$(mktemp "$SANDBOX_BASE/out.XXXXXX")
bash "$REPO_ROOT/uninstall.sh" >"$out_file" 2>&1
ec=$?
if [ "$ec" -eq 0 ] && grep -qi 'not installed\|does not exist' "$out_file"; then
  _record "uninstall when absent → exit 0, idempotent" 0
else
  _record "uninstall when absent → exit 0, idempotent" 1 \
    "exit=$ec; output: $(cat "$out_file")"
fi

# Scenario 11: uninstall with PLANE_INSTALL_ROOT outside ~/.claude/skills/plane → refuse.
printf '== error: uninstall refuses non-skill path ==\n'
_sandbox uninstall-wrong-path
bad_path="$SANDBOX_BASE/uninstall-wrong-path/elsewhere"
mkdir -p "$bad_path"
touch "$bad_path/sentinel"
export PLANE_INSTALL_ROOT="$bad_path"
out_file=$(mktemp "$SANDBOX_BASE/out.XXXXXX")
bash "$REPO_ROOT/uninstall.sh" >"$out_file" 2>&1
ec=$?
if [ "$ec" -eq 1 ] && [ -f "$bad_path/sentinel" ] && grep -qi 'refusing' "$out_file"; then
  _record "uninstall refuses path outside ~/.claude/skills/plane" 0
else
  _record "uninstall refuses path outside ~/.claude/skills/plane" 1 \
    "exit=$ec; sentinel_present=$([ -f "$bad_path/sentinel" ] && echo yes || echo no); output: $(cat "$out_file")"
fi

# Summary
printf '\n== install.test.sh summary ==\n'
printf 'pass: %d\nfail: %d\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'failures:%s\n' "$failures" >&2
  exit 1
fi
exit 0
