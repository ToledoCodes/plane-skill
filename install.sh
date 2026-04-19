#!/bin/bash
# install.sh — install the `plane` skill to ~/.claude/skills/plane/
# Bash 3.2 compatible. Runs on fresh macOS before `brew install bash`.
#
# Usage:
#   ./install.sh           # copy mode (default)
#   ./install.sh --symlink # symlink mode
#   ./install.sh --help
#
# Exit codes:
#   0  success (or already installed at same SHA)
#   1  generic error
#   2  argument parse
#   3  config / environment problem (e.g. ~/.claude/.plane missing, source outside $HOME)
set -u

INSTALL_ROOT="${PLANE_INSTALL_ROOT:-${HOME}/.claude/skills/plane}"
CONFIG_PATH="${PLANE_CONFIG_PATH:-${HOME}/.claude/.plane}"
MODE="copy"

while [ $# -gt 0 ]; do
  case "$1" in
    --symlink) MODE="symlink"; shift ;;
    --copy)    MODE="copy"; shift ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --) shift; break ;;
    *)
      printf 'install.sh: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

# Resolve source repo path portably (no readlink -f on macOS 3.2 without coreutils).
_resolve_path() {
  # $1 is a path that should already exist. Echo its absolute form.
  # Uses cd + pwd -P, which is POSIX-portable.
  local target="$1"
  if [ -d "$target" ]; then
    (cd "$target" && pwd -P)
  else
    local d f
    d=$(dirname "$target")
    f=$(basename "$target")
    (cd "$d" && printf '%s/%s\n' "$(pwd -P)" "$f")
  fi
}

SOURCE_DIR=$(_resolve_path "$(dirname "$0")")

if [ "${PLANE_ALLOW_ANY_SOURCE:-0}" != "1" ]; then
  case "$SOURCE_DIR" in
    "$HOME"|"$HOME"/*) : ;;
    *)
      printf 'install.sh: source repo must live under $HOME (got: %s)\n' "$SOURCE_DIR" >&2
      exit 3
      ;;
  esac
fi

# Bash version gate for the plane CLI itself (not this installer).
# We don't exec under bash 4 — we just tell the user what to do.
if [ -z "${BASH_VERSINFO+x}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  case "$(uname -s)" in
    Darwin)
      if [ ! -x /opt/homebrew/bin/bash ] && [ ! -x /usr/local/bin/bash ]; then
        cat <<EOF >&2
install.sh: the plane CLI requires bash >= 4, and no brewed bash was found.

Install bash via Homebrew:
  brew install bash

Then re-run ./install.sh. Your login shell can stay as-is — the plane CLI uses
its own shebang and ignores your user shell choice.
EOF
        exit 3
      fi
      # Brewed bash present; we don't need to exec under it. Continue.
      ;;
    *)
      printf 'install.sh: bash >= 4 required (have %s).\n' "${BASH_VERSION:-unknown}" >&2
      exit 3
      ;;
  esac
fi

# Config preflight: ~/.claude/.plane must exist. Don't scaffold it; the user
# reads docs/contract-claude-plane.md and decides what to put there.
if [ ! -f "$CONFIG_PATH" ]; then
  cat <<EOF >&2
install.sh: $CONFIG_PATH does not exist.

Create it by running:
  cp $SOURCE_DIR/docs/example-plane-config $CONFIG_PATH && chmod 600 $CONFIG_PATH

Edit the values to match your Plane workspace, then set your API key in your
shell profile:
  export PLANE_API_KEY=plane_api_...   # or whichever name you use in api_key_env

Then re-run ./install.sh.
EOF
  exit 3
fi

# Config mode check. Warn on broader than 0600; do not rewrite.
# `stat` flags differ between macOS (-f) and GNU (-c); handle both.
CONFIG_MODE=""
if CONFIG_MODE=$(stat -f '%Lp' "$CONFIG_PATH" 2>/dev/null); then :
elif CONFIG_MODE=$(stat -c '%a' "$CONFIG_PATH" 2>/dev/null); then :
fi
case "$CONFIG_MODE" in
  600|400) : ;;
  "")
    printf 'install.sh: warning — could not read mode of %s\n' "$CONFIG_PATH" >&2
    ;;
  *)
    printf 'install.sh: warning — %s has mode %s (recommend 0600).\n' "$CONFIG_PATH" "$CONFIG_MODE" >&2
    ;;
esac

# Idempotency: if the install dir already exists at the same git SHA, exit 0.
CURRENT_SHA=""
if command -v git >/dev/null 2>&1 && [ -d "$SOURCE_DIR/.git" ]; then
  CURRENT_SHA=$(cd "$SOURCE_DIR" && git rev-parse HEAD 2>/dev/null || true)
fi

if [ -d "$INSTALL_ROOT" ] && [ -f "$INSTALL_ROOT/.install-sha" ]; then
  PREV_SHA=$(cat "$INSTALL_ROOT/.install-sha" 2>/dev/null || true)
  if [ -n "$CURRENT_SHA" ] && [ "$CURRENT_SHA" = "$PREV_SHA" ]; then
    printf 'plane already installed at %s (SHA %s).\n' "$INSTALL_ROOT" "$CURRENT_SHA"
    exit 0
  fi
fi

# Fresh-install path: wipe a prior install to avoid stale files, then write.
if [ -e "$INSTALL_ROOT" ] || [ -L "$INSTALL_ROOT" ]; then
  # Safety: refuse anything whose resolved path escapes ~/.claude/skills/plane.
  RESOLVED=$(_resolve_path "$INSTALL_ROOT" 2>/dev/null || printf '%s' "$INSTALL_ROOT")
  EXPECTED="$HOME/.claude/skills/plane"
  EXPECTED_RESOLVED=$(_resolve_path "$HOME/.claude/skills" 2>/dev/null || printf '%s/.claude/skills' "$HOME")
  case "$RESOLVED" in
    "$EXPECTED"|"$EXPECTED_RESOLVED/plane") rm -rf "$INSTALL_ROOT" ;;
    *)
      printf 'install.sh: refusing to remove %s (resolves outside ~/.claude/skills/plane).\n' "$INSTALL_ROOT" >&2
      exit 1
      ;;
  esac
fi

mkdir -p "$(dirname "$INSTALL_ROOT")" || {
  printf 'install.sh: could not create parent of %s\n' "$INSTALL_ROOT" >&2
  exit 1
}

case "$MODE" in
  symlink)
    ln -s "$SOURCE_DIR" "$INSTALL_ROOT" || {
      printf 'install.sh: symlink failed (%s -> %s)\n' "$INSTALL_ROOT" "$SOURCE_DIR" >&2
      exit 1
    }
    ;;
  copy)
    mkdir -p "$INSTALL_ROOT" || exit 1
    # Copy with attributes. Exclude .git and test/tmp noise.
    (
      cd "$SOURCE_DIR" && \
      find . -type d \( -name .git -o -name tmp -o -name out \) -prune -o -print | \
      while IFS= read -r entry; do
        case "$entry" in
          .) continue ;;
        esac
        rel=${entry#./}
        dest="$INSTALL_ROOT/$rel"
        if [ -d "$entry" ]; then
          mkdir -p "$dest"
        else
          cp -p "$entry" "$dest"
        fi
      done
    ) || { printf 'install.sh: copy failed\n' >&2; exit 1; }
    ;;
esac

# Record install SHA for idempotency + uninstall sanity checks.
if [ -n "$CURRENT_SHA" ]; then
  case "$MODE" in
    symlink)
      # The SHA lives in the source repo, not inside the symlink target.
      # Write to a sibling file so uninstall.sh can still read it.
      printf '%s\n' "$CURRENT_SHA" > "$INSTALL_ROOT.install-sha"
      ;;
    copy)
      printf '%s\n' "$CURRENT_SHA" > "$INSTALL_ROOT/.install-sha"
      ;;
  esac
fi

printf 'plane installed (%s mode) at %s\n' "$MODE" "$INSTALL_ROOT"
exit 0
