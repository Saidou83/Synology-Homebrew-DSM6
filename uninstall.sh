#!/bin/sh
# uninstall.sh
#
# Reverses everything install.sh (and the optional extras) can set up:
#   - stops and removes the optional Tailscale rc.d script
#   - reverts the optional forced login shell
#   - removes the core rc.d scripts (os-release generator, /home mount)
#   - unmounts /home
#   - removes the /usr/bin/ldd shim
#   - removes /etc/os-release
#   - optionally uninstalls Homebrew itself (via the official uninstaller)
#
# Nothing destructive happens without an explicit prompt. Answering "no"
# (or just pressing enter) to any prompt skips that step.
#
# Usage:
#   sudo sh uninstall.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo sh uninstall.sh)." >&2
  exit 1
fi

RC_D="/usr/local/etc/rc.d"

confirm() {
  # confirm "question" -> returns 0 for yes, 1 for no (default no)
  printf "%s [y/N]: " "$1"
  read -r ans
  case "$ans" in
    y|Y|yes|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

echo "== Homebrew on DSM 6 — uninstaller =="
echo "This will walk through removing each piece. You'll be asked before"
echo "anything destructive happens."
echo

# ---------------------------------------------------------------------
# 1. Optional: Tailscale extra
# ---------------------------------------------------------------------

if [ -f "$RC_D/S11-tailscaled.sh" ]; then
  echo "-- Optional extra: Tailscale --"
  if confirm "Stop tailscaled and remove S11-tailscaled.sh?"; then
    BREW_PREFIX_GUESS=$(awk -F'"' '/^BREW_PREFIX=/{print $2}' "$RC_D/S11-tailscaled.sh")
    if [ -n "$BREW_PREFIX_GUESS" ]; then
      pkill -f "${BREW_PREFIX_GUESS}/bin/tailscaled" 2>/dev/null || true
    fi
    rm -f "$RC_D/S11-tailscaled.sh"
    echo "Removed. (Tailscale's own auth/state is untouched — 'brew uninstall"
    echo "tailscale' separately if you want it fully gone, and sign the node"
    echo "out from https://login.tailscale.com/admin/machines if it's no"
    echo "longer needed on your tailnet.)"
  fi
  echo
fi

# ---------------------------------------------------------------------
# 2. Optional: forced login shell
# ---------------------------------------------------------------------

if [ -f "$RC_D/S10-force-zsh.sh" ]; then
  echo "-- Optional extra: forced login shell --"
  TARGET_USER_GUESS=$(awk -F'"' '/^TARGET_USER=/{print $2}' "$RC_D/S10-force-zsh.sh")
  if confirm "Remove S10-force-zsh.sh (stops re-applying the shell at boot)?"; then
    rm -f "$RC_D/S10-force-zsh.sh"
    echo "Removed."
    if [ -n "$TARGET_USER_GUESS" ]; then
      if confirm "Also revert ${TARGET_USER_GUESS}'s login shell right now (to /bin/sh)?"; then
        CURRENT_SHELL=$(awk -F: -v u="$TARGET_USER_GUESS" '$1==u{print $NF}' /etc/passwd)
        if [ -n "$CURRENT_SHELL" ]; then
          sed -i.bak "$(awk -F: -v u="$TARGET_USER_GUESS" '$1==u{print NR}' /etc/passwd)s|${CURRENT_SHELL}|/bin/sh|" /etc/passwd
          echo "Reverted ${TARGET_USER_GUESS}'s shell to /bin/sh."
        fi
      fi
    fi
  fi
  echo
fi

# ---------------------------------------------------------------------
# 3. Core rc.d scripts
# ---------------------------------------------------------------------

echo "-- Core rc.d scripts --"
if confirm "Remove S00-generate-os-release.sh and S01-homebrew-mount.sh?"; then
  rm -f "$RC_D/S00-generate-os-release.sh" "$RC_D/S01-homebrew-mount.sh"
  echo "Removed."
fi
echo

# ---------------------------------------------------------------------
# 4. Unmount /home
# ---------------------------------------------------------------------

echo "-- /home bind mount --"
if grep -qs ' /home ' /proc/mounts; then
  if confirm "Unmount /home now?"; then
    umount /home
    echo "Unmounted. (Your actual files under the homes share are untouched —"
    echo "this only removes the bind mount, not any data.)"
  fi
else
  echo "/home is not currently mounted, nothing to do."
fi
echo

# ---------------------------------------------------------------------
# 5. ldd shim
# ---------------------------------------------------------------------

if [ -f /usr/bin/ldd ]; then
  echo "-- ldd shim --"
  if confirm "Remove /usr/bin/ldd?"; then
    rm -f /usr/bin/ldd
    echo "Removed."
  fi
  echo
fi

# ---------------------------------------------------------------------
# 6. os-release
# ---------------------------------------------------------------------

if [ -f /etc/os-release ]; then
  echo "-- /etc/os-release --"
  if confirm "Remove /etc/os-release?"; then
    rm -f /etc/os-release
    echo "Removed."
  fi
  echo
fi

# ---------------------------------------------------------------------
# 7. Homebrew itself
# ---------------------------------------------------------------------

echo "-- Homebrew itself --"
echo "This is the biggest step: it removes Homebrew and everything you've"
echo "installed with 'brew install ...' (formulae, casks, caches)."
if confirm "Uninstall Homebrew itself using the official uninstaller?"; then
  echo "Running the official Homebrew uninstall script..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
else
  echo "Skipped. Homebrew and its installed packages are left in place."
fi

echo
echo "== Done =="
echo "If you unmounted /home and skipped uninstalling Homebrew, your"
echo "Homebrew files still exist on disk (under your homes share) but"
echo "won't be reachable at /home/linuxbrew/.linuxbrew until you mount"
echo "/home again (e.g. by re-running S01-homebrew-mount.sh, or manually:"
echo "  sudo mount -o bind /volume1/homes /home"
echo ")."
