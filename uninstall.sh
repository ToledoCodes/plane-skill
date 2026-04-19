#!/bin/bash
# uninstall.sh — remove the `plane` skill from ~/.claude/skills/plane/
# Bash 3.2 compatible. Refuses to remove anything outside ~/.claude/skills/plane.
#
# Usage:
#   ./uninstall.sh
#   ./uninstall.sh --help
#
# Exit codes:
#   0  success (or already absent)
#   1  generic error (e.g. resolves outside the expected install path)
#   2  argument parse
set -u

INSTALL_ROOT="${PLANE_INSTALL_ROOT:-${HOME}/.claude/skills/plane}"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --) shift; break ;;
    *)
      printf 'uninstall.sh: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

_resolve_path() {
  local target="$1"
  if [ -d "$target" ]; then
    (cd "$target" && pwd -P)
  elif [ -L "$target" ]; then
    # Resolve the symlink by looking at what it points to.
    local link_target
    link_target=$(readlink "$target" 2>/dev/null || true)
    if [ -z "$link_target" ]; then
      printf '%s' "$target"
      return
    fi
    case "$link_target" in
      /*) _resolve_path "$link_target" ;;
      *)  _resolve_path "$(dirname "$target")/$link_target" ;;
    esac
  elif [ -e "$target" ]; then
    local d f
    d=$(dirname "$target")
    f=$(basename "$target")
    (cd "$d" && printf '%s/%s\n' "$(pwd -P)" "$f")
  else
    printf '%s' "$target"
  fi
}

if [ ! -e "$INSTALL_ROOT" ] && [ ! -L "$INSTALL_ROOT" ]; then
  printf 'plane is not installed (%s does not exist).\n' "$INSTALL_ROOT"
  # Clean up the sidecar SHA file from a symlink install, if any.
  rm -f "$INSTALL_ROOT.install-sha" 2>/dev/null || true
  exit 0
fi

# Safety: refuse anything whose *path* sits outside ~/.claude/skills/plane.
# We purposely check INSTALL_ROOT itself, not where the symlink points —
# a symlink install resolves into the source repo, which is legitimate.
CANONICAL_PARENT=$(_resolve_path "$HOME/.claude/skills" 2>/dev/null || printf '%s/.claude/skills' "$HOME")
EXPECTED="$CANONICAL_PARENT/plane"

# INSTALL_ROOT may be a symlink. Compare the path itself, not its target.
case "$INSTALL_ROOT" in
  "$HOME/.claude/skills/plane"|"$EXPECTED") : ;;
  *)
    printf 'uninstall.sh: refusing to touch %s (not ~/.claude/skills/plane).\n' "$INSTALL_ROOT" >&2
    exit 1
    ;;
esac

# If it's a symlink, rm -rf follows the symlink file itself, not its target.
# That's the desired behavior.
rm -rf "$INSTALL_ROOT" || {
  printf 'uninstall.sh: rm -rf failed on %s\n' "$INSTALL_ROOT" >&2
  exit 1
}
rm -f "$INSTALL_ROOT.install-sha" 2>/dev/null || true

printf 'plane uninstalled (%s removed).\n' "$INSTALL_ROOT"
exit 0
