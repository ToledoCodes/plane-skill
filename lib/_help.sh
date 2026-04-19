#!/usr/bin/env bash
# Summary: lazy help tree — greps # Summary: across lib/*.sh without sourcing.
# Usage:   sourced by bin/plane; consumers call _help_all / _help_for / _help_root.
[ "${__PLANE_HELP_LOADED:-0}" = "1" ] && return 0
__PLANE_HELP_LOADED=1

# Resolved at source time so tests can override via PLANE_LIB_DIR.
_HELP_LIB_DIR="${PLANE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"

# _help_root: top-level help. Prints dispatcher usage + greps # Summary:
# across lib/*.sh. Does NOT source any resource lib.
_help_root() {
  cat <<'EOF'
plane — Plane.so REST CLI

Usage:
  plane <resource> <action> [args]
  plane <meta> [args]

Global flags:
  --workspace <slug>       Override configured workspace
  --api-url <url>          Override configured API URL (https:// only)
  --json                   Force raw JSON output (even on TTY)
  --pretty                 Force human-readable summary (even when piped)
  --no-color               Disable ANSI colors
  --follow-redirects       Follow 3xx redirects
  --connect-timeout <sec>  Override connect timeout (default 10)
  --max-time <sec>         Override total max time (default 60)
  --help, -h               Show this help
  --version, -v            Print version info

Meta commands:
  help [<resource>]        Deep help for a resource
  version                  Version info (offline, no network)
  doctor                   Environment checks
  resolve <IDENT-123>      Resolve a work-item identifier to its object
  api <METHOD> <path>      Escape hatch to any Plane endpoint

Resources:
EOF
  _help_summaries
  cat <<'EOF'

For per-resource help:
  plane help <resource>
  plane <resource> --help
  plane <resource> <action> --help
EOF
}

# _help_summaries: print "  <resource>    <summary>" for every lib/*.sh
# that carries a `# Summary:` header. Meta libs (filenames starting with
# `_` or named doctor/version/resolve/api/_help/_core/_parse/_endpoint_map)
# are filtered out.
_help_summaries() {
  local f base resource summary
  for f in "$_HELP_LIB_DIR"/*.sh; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .sh)
    case "$base" in
      _*|doctor|version|resolve|api) continue ;;
    esac
    # Grep the first `# Summary:` line — bounded to the top of the file
    # so we never read more than a few lines.
    summary=$(grep -m 1 '^# Summary:' "$f" 2>/dev/null \
                | sed 's/^# Summary: *//')
    [ -z "$summary" ] && summary="(no summary)"
    printf '  %-14s %s\n' "$base" "$summary"
  done | sort
}

# _help_for <resource>: sources ONLY lib/<resource>.sh and calls
# _help_resource_<resource>. Unknown resource → exit 2.
_help_for() {
  local resource="$1" path fn
  path="$_HELP_LIB_DIR/$resource.sh"
  if [ ! -f "$path" ]; then
    printf 'plane: unknown resource: %s\n' "$resource" >&2
    return 2
  fi
  # shellcheck disable=SC1090  # dynamic path by design
  . "$path"
  # time-entries resource → _help_resource_time_entries (dashes to underscores).
  fn="_help_resource_${resource//-/_}"
  if declare -F "$fn" >/dev/null; then
    "$fn"
    return 0
  fi
  printf 'plane: %s has no per-resource help function\n' "$resource" >&2
  return 1
}
