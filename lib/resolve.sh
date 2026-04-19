#!/usr/bin/env bash
# Summary: resolve a human identifier (e.g. PROJ-123) to its work-item object.
# Usage:   plane resolve <IDENT-N>
[ "${__PLANE_RESOLVE_LOADED:-0}" = "1" ] && return 0
__PLANE_RESOLVE_LOADED=1

_resolve_cmd() {
  local ident=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        cat <<'EOF'
plane resolve — resolve a work-item identifier to its full object

Usage: plane resolve <IDENT-N>

Example: plane resolve PROJ-123 — returns the work-item matching the
Plane-issued `<project_identifier>-<sequence>` form. Equivalent to
GET /api/v1/workspaces/<slug>/issues/<IDENT-N>/ (the `issues/` alias
is used; `work-items/` also works server-side).

Output: JSON on a pipe, terse summary on a TTY.
EOF
        return 0
        ;;
      --) shift; break ;;
      -*) printf 'plane resolve: unknown flag: %s\n' "$1" >&2; return 2 ;;
      *)
        if [ -z "$ident" ]; then
          ident="$1"
          shift
        else
          printf 'plane resolve: unexpected arg: %s\n' "$1" >&2
          return 2
        fi
        ;;
    esac
  done

  if [ -z "$ident" ]; then
    printf 'plane resolve: identifier required (e.g. PROJ-123)\n' >&2
    return 2
  fi

  # Quick syntax check so we exit 2 on obvious bad input instead of 404.
  case "$ident" in
    *-*) : ;;
    *) printf 'plane resolve: identifier must be <PROJ>-<N> (got: %s)\n' "$ident" >&2; return 2 ;;
  esac

  _core_preflight
  _core_config_resolve

  local out body
  # Path "/issues/<ident>/" is workspace-scoped per _core_build_url rules.
  out=$(_core_http GET "/issues/$ident/") || return $?
  # Split "<status>\t<body-path>" — we route by exit code, not status here.
  body="${out#*$'\t'}"

  if [ -t 1 ] && [ -z "${PLANE_FORCE_JSON:-}" ]; then
    # TTY summary.
    jq -r '
      "\(.project_identifier // "?")-\(.sequence_id)  \(.name // "(no name)")" ,
      "  id:       \(.id)",
      "  state:    \(.state)",
      "  priority: \(.priority // "none")",
      "  project:  \(.project)"
    ' "$body" 2>/dev/null || cat "$body"
  else
    cat "$body"
  fi
}
