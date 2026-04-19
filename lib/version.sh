#!/usr/bin/env bash
# Summary: print plane version, tool versions, and captured-spec timestamp (no network).
# Usage:   plane version
[ "${__PLANE_VERSION_LOADED:-0}" = "1" ] && return 0
__PLANE_VERSION_LOADED=1

_version_cmd() {
  local install_sha="dev"
  # Prefer an explicit override. Otherwise fall back to the directory that
  # actually contains this lib — which is correct whether we're running from
  # the source repo or from an installed copy.
  local install_root
  if [ -n "${PLANE_INSTALL_ROOT:-}" ]; then
    install_root="$PLANE_INSTALL_ROOT"
  elif [ -n "${PLANE_LIB_DIR:-}" ]; then
    install_root=$(dirname "$PLANE_LIB_DIR")
  else
    install_root="$HOME/.claude/skills/plane"
  fi
  local sha_path=""
  if [ -f "$install_root/.install-sha" ]; then
    sha_path="$install_root/.install-sha"
  elif [ -f "$install_root.install-sha" ]; then
    sha_path="$install_root.install-sha"
  fi
  [ -n "$sha_path" ] && install_sha=$(tr -d '\n' < "$sha_path" 2>/dev/null || echo "dev")

  local bash_actual="${BASH_VERSION:-unknown}"
  local curl_actual jq_actual
  curl_actual=$(command -v curl >/dev/null 2>&1 && curl --version 2>/dev/null | head -1 | awk '{print $2}')
  jq_actual=$(command -v jq >/dev/null 2>&1 && jq --version 2>/dev/null | sed 's/^jq-//')
  [ -z "$curl_actual" ] && curl_actual="missing"
  [ -z "$jq_actual" ] && jq_actual="missing"

  # Spec timestamp: newest docs/plane-openapi-*.yaml in the install root.
  local spec_ts="none"
  local spec
  for spec in "$install_root"/docs/plane-openapi-*.yaml; do
    [ -f "$spec" ] || continue
    # Extract timestamp from filename: plane-openapi-<TS>.yaml
    local name ts
    name=$(basename "$spec" .yaml)
    ts=${name#plane-openapi-}
    spec_ts="$ts"
  done

  cat <<EOF
plane $install_sha
  bash:  $bash_actual (min 4)
  curl:  $curl_actual
  jq:    $jq_actual (min 1.6)
  spec:  $spec_ts
  root:  $install_root
EOF
}
