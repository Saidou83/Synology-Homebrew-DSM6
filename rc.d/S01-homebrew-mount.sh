#!/bin/sh
# S01-homebrew-mount.sh
#
# Homebrew must be installed at /home/linuxbrew/.linuxbrew to be able to
# download prebuilt binaries ("bottles"). DSM has no /home directory --
# user homes live under /volume1/homes (symlinked from
# /var/services/homes). A plain symlink is NOT enough: Homebrew resolves
# real paths, so it would "see" /volume1/homes/linuxbrew/.linuxbrew and
# refuse to use prebuilt bottles, forcing slow/fragile source builds
# (which will fail outright for anything needing a C compiler, since
# DSM doesn't ship one).
#
# A bind mount solves this: /home becomes a real mount point backed by
# /volume1/homes, so Homebrew sees a genuine /home/linuxbrew/.linuxbrew
# path.
#
# EDIT THIS if your homes share isn't at /volume1/homes (e.g. a
# different volume number).
SOURCE_DIR="/volume1/homes"
TARGET_DIR="/home"

case "$1" in
  start)
    mkdir -p "$TARGET_DIR"

    if ! grep -qs " ${TARGET_DIR} " /proc/mounts; then
      mount -o bind "$SOURCE_DIR" "$TARGET_DIR"
    fi
    ;;
  stop)
    umount "$TARGET_DIR" 2>/dev/null || true
    ;;
  *)
    echo "Usage: $0 {start|stop}" >&2
    exit 1
    ;;
esac
