#!/bin/sh
# bootstrap.sh
#
# Entry point for running this repo as a one-liner, the same way
# Homebrew's own installer works:
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/<you>/synology-homebrew-dsm6/main/bootstrap.sh)" -- --install
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/<you>/synology-homebrew-dsm6/main/bootstrap.sh)" -- --uninstall
#
# Downloads a tarball of this repo into a temp directory and hands off
# to install.sh or uninstall.sh. Requires curl and tar (both present on
# stock DSM 6).
#
# Options:
#   --install     Run install.sh (default if no option given)
#   --uninstall   Run uninstall.sh
#   --branch=X    Use a specific branch/tag instead of "main"
#   --keep        Don't delete the downloaded copy afterwards
#   -h, --help    Show this help
#
# You can also run this script directly if you've already cloned the
# repo -- it will just use the local copy instead of downloading.

set -e

# EDIT THIS after you push the repo to your own GitHub account/org.
REPO_OWNER="Saidou83"
REPO_NAME="homebrew-synology-dsm6"
BRANCH="main"

ACTION="install"
KEEP=0

for arg in "$@"; do
  case "$arg" in
    --install) ACTION="install" ;;
    --uninstall) ACTION="uninstall" ;;
    --branch=*) BRANCH="${arg#--branch=}" ;;
    --keep) KEEP=1 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

# ---------------------------------------------------------------------
# If we're already inside a checked-out copy of the repo (has
# install.sh next to us), just use it directly -- no download needed.
# ---------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/install.sh" ] && [ -f "$SCRIPT_DIR/uninstall.sh" ]; then
  WORKDIR="$SCRIPT_DIR"
  CLEANUP=0
else
  echo "Downloading synology-homebrew-dsm6 (${BRANCH})..."
  WORKDIR=$(mktemp -d)
  CLEANUP=1

  TARBALL_URL="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/tar.gz/refs/heads/${BRANCH}"

  if ! curl -fsSL "$TARBALL_URL" | tar -xz -C "$WORKDIR" --strip-components=1; then
    echo "Failed to download ${TARBALL_URL}" >&2
    echo "Check REPO_OWNER/REPO_NAME/BRANCH at the top of bootstrap.sh." >&2
    rm -rf "$WORKDIR"
    exit 1
  fi
fi

# ---------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------

case "$ACTION" in
  install)
    sh "$WORKDIR/install.sh"
    ;;
  uninstall)
    sh "$WORKDIR/uninstall.sh"
    ;;
esac

if [ "$CLEANUP" -eq 1 ] && [ "$KEEP" -eq 0 ]; then
  rm -rf "$WORKDIR"
elif [ "$CLEANUP" -eq 1 ] && [ "$KEEP" -eq 1 ]; then
  echo "Downloaded copy kept at: $WORKDIR"
fi
