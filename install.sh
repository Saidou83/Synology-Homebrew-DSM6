#!/bin/sh
# install.sh
#
# One-shot installer for Homebrew on DSM 6, boot-persistent.
#
# Core steps (always run):
#   1. ldd shim
#   2. bind-mount /home
#   3. install Homebrew
#   4. install rc.d scripts that keep 1-3 working after a reboot
#
# Optional extras (prompted for at the end, skipped by default):
#   - force a custom login shell (e.g. Homebrew zsh) at boot
#   - run a Homebrew-installed tailscaled at boot
#
# Safe to re-run — steps that are already done (ldd shim, mount, rc.d
# scripts) are simply overwritten/skipped as appropriate.
#
# Usage:
#   sudo sh install.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo sh install.sh)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== Homebrew on DSM 6 — installer =="
echo

# ---------------------------------------------------------------------
# Core prompts
# ---------------------------------------------------------------------

DEFAULT_SOURCE_DIR="/volume1/homes"
printf "Path to your DSM homes share [%s]: " "$DEFAULT_SOURCE_DIR"
read -r SOURCE_DIR
SOURCE_DIR="${SOURCE_DIR:-$DEFAULT_SOURCE_DIR}"

DEFAULT_BREW_PREFIX="/home/linuxbrew/.linuxbrew"
printf "Homebrew prefix [%s]: " "$DEFAULT_BREW_PREFIX"
read -r BREW_PREFIX
BREW_PREFIX="${BREW_PREFIX:-$DEFAULT_BREW_PREFIX}"

echo
echo "Summary:"
echo "  Homes share:     $SOURCE_DIR"
echo "  Homebrew prefix: $BREW_PREFIX"
printf "Continue? [Y/n]: "
read -r ans
case "$ans" in
  n|N|no|No) echo "Aborted."; exit 0 ;;
esac

# ---------------------------------------------------------------------
# 1. ldd shim
# ---------------------------------------------------------------------

echo
echo "-- Installing ldd shim --"
sh "$SCRIPT_DIR/setup/ldd-shim.sh"

# ---------------------------------------------------------------------
# 2. Bind mount /home (needed now so Homebrew can install)
# ---------------------------------------------------------------------

echo
echo "-- Bind-mounting $SOURCE_DIR to /home --"
mkdir -p /home
if ! grep -qs ' /home ' /proc/mounts; then
  mount -o bind "$SOURCE_DIR" /home
else
  echo "/home already mounted, skipping."
fi

# ---------------------------------------------------------------------
# 3. Install Homebrew (if not already installed)
# ---------------------------------------------------------------------

echo
if [ -x "$BREW_PREFIX/bin/brew" ]; then
  echo "-- Homebrew already installed at $BREW_PREFIX, skipping install --"
else
  echo "-- Installing Homebrew --"
  echo "You will be prompted by the official installer. When asked for an"
  echo "install location, choose: $BREW_PREFIX"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# ---------------------------------------------------------------------
# 4. Install core rc.d scripts (keep the above working after reboot)
# ---------------------------------------------------------------------

echo
echo "-- Installing core rc.d scripts --"
mkdir -p /usr/local/etc/rc.d

cp "$SCRIPT_DIR/rc.d/S00-generate-os-release.sh" /usr/local/etc/rc.d/
chmod +x /usr/local/etc/rc.d/S00-generate-os-release.sh
echo "Installed S00-generate-os-release.sh"

sed -e "s|^SOURCE_DIR=.*|SOURCE_DIR=\"$SOURCE_DIR\"|" \
  "$SCRIPT_DIR/rc.d/S01-homebrew-mount.sh" > /usr/local/etc/rc.d/S01-homebrew-mount.sh
chmod +x /usr/local/etc/rc.d/S01-homebrew-mount.sh
echo "Installed S01-homebrew-mount.sh"

echo
echo "-- Running core rc.d scripts now --"
for f in /usr/local/etc/rc.d/S00-generate-os-release.sh /usr/local/etc/rc.d/S01-homebrew-mount.sh; do
  echo "Running $f start"
  sh "$f" start
done

echo
echo "== Core install done =="
echo "Homebrew is installed at $BREW_PREFIX and will survive reboots."

# ---------------------------------------------------------------------
# Optional extras
# ---------------------------------------------------------------------

echo
echo "== Optional extras =="
echo "Everything below is optional and unrelated to Homebrew itself."
echo

printf "Force a custom login shell (e.g. Homebrew zsh) at boot? [y/N]: "
read -r ans
case "$ans" in
  y|Y|yes|Yes)
    CURRENT_USER="${SUDO_USER:-}"
    printf "DSM username to switch shells for [%s]: " "$CURRENT_USER"
    read -r TARGET_USER
    TARGET_USER="${TARGET_USER:-$CURRENT_USER}"

    if [ -n "$TARGET_USER" ]; then
      sed -e "s|^TARGET_USER=.*|TARGET_USER=\"$TARGET_USER\"|" \
        "$SCRIPT_DIR/optional/S10-force-zsh.sh" > /usr/local/etc/rc.d/S10-force-zsh.sh
      chmod +x /usr/local/etc/rc.d/S10-force-zsh.sh
      echo "Installed S10-force-zsh.sh"
      echo "Note: this assumes /bin/zsh exists (often a symlink to your"
      echo "zsh binary, e.g. a community-package or Homebrew build)."
      echo "Check with: ls -la /bin/zsh"
      sh /usr/local/etc/rc.d/S10-force-zsh.sh start
    else
      echo "No username given, skipping."
    fi
    ;;
esac

echo
printf "Set up Tailscale, installed via Homebrew, to run at boot? [y/N]: "
read -r ans
case "$ans" in
  y|Y|yes|Yes)
    BREW_BIN="$BREW_PREFIX/bin/brew"
    TAILSCALED_BIN="$BREW_PREFIX/bin/tailscaled"
    TAILSCALE_BIN="$BREW_PREFIX/bin/tailscale"
    SOCKET="/var/run/tailscale/tailscaled.sock"

    if [ ! -x "$BREW_BIN" ]; then
      echo "S11-tailscaled: $BREW_BIN not found, can't install tailscale. Skipping." >&2
    else
      # Homebrew refuses to run as root, so run it as the user who owns
      # the Homebrew prefix (falling back to $SUDO_USER, then whoever
      # invoked sudo).
      BREW_OWNER=$(stat -c '%U' "$BREW_PREFIX" 2>/dev/null || echo "${SUDO_USER:-root}")

      if [ -x "$TAILSCALED_BIN" ]; then
        echo "tailscale already installed via Homebrew, skipping 'brew install'."
      else
        echo "Installing tailscale via Homebrew (as user: $BREW_OWNER)..."
        sudo -u "$BREW_OWNER" "$BREW_BIN" install tailscale
      fi
    fi

    if [ -x "$TAILSCALED_BIN" ]; then
      sed -e "s|^BREW_PREFIX=.*|BREW_PREFIX=\"$BREW_PREFIX\"|" \
        "$SCRIPT_DIR/optional/S11-tailscaled.sh" > /usr/local/etc/rc.d/S11-tailscaled.sh
      chmod +x /usr/local/etc/rc.d/S11-tailscaled.sh
      echo "Installed S11-tailscaled.sh"

      echo "Starting tailscaled..."
      sh /usr/local/etc/rc.d/S11-tailscaled.sh start
      sleep 2

      echo "Running 'tailscale up' (you may be asked to visit an auth URL)..."
      "$TAILSCALE_BIN" --socket="$SOCKET" up || true
    else
      echo "tailscaled binary still not found after install attempt — skipping" >&2
      echo "daemon start. Check the brew install output above." >&2
    fi
    ;;
esac

echo
echo "== Done =="
echo "Reboot to confirm everything comes up automatically:"
echo "  sudo reboot"
echo "Then check:"
echo "  mount | grep /home"
echo "  cat /etc/os-release"
