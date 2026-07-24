#!/bin/sh
# install.sh
#
# One-shot installer: runs every step from the README in order, prompting
# for the values each rc.d script needs, then writes and installs them.
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
# Prompts
# ---------------------------------------------------------------------

DEFAULT_SOURCE_DIR="/volume1/homes"
printf "Path to your DSM homes share [%s]: " "$DEFAULT_SOURCE_DIR"
read -r SOURCE_DIR
SOURCE_DIR="${SOURCE_DIR:-$DEFAULT_SOURCE_DIR}"

CURRENT_USER="${SUDO_USER:-}"
printf "DSM username to switch to zsh (leave blank to skip) [%s]: " "$CURRENT_USER"
read -r TARGET_USER
TARGET_USER="${TARGET_USER:-$CURRENT_USER}"

DEFAULT_BREW_PREFIX="/home/linuxbrew/.linuxbrew"
printf "Homebrew prefix [%s]: " "$DEFAULT_BREW_PREFIX"
read -r BREW_PREFIX
BREW_PREFIX="${BREW_PREFIX:-$DEFAULT_BREW_PREFIX}"

INSTALL_TAILSCALE="n"
printf "Set up Homebrew tailscaled at boot too? [y/N]: "
read -r ans
case "$ans" in
  y|Y|yes|Yes) INSTALL_TAILSCALE="y" ;;
esac

echo
echo "Summary:"
echo "  Homes share:     $SOURCE_DIR"
echo "  Zsh user:        ${TARGET_USER:-<skip>}"
echo "  Homebrew prefix: $BREW_PREFIX"
echo "  Set up tailscaled: $INSTALL_TAILSCALE"
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
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# ---------------------------------------------------------------------
# 4. Write rc.d scripts with the values above baked in
# ---------------------------------------------------------------------

echo
echo "-- Installing rc.d scripts --"
mkdir -p /usr/local/etc/rc.d

# S00: force zsh (only if a user was given)
if [ -n "$TARGET_USER" ]; then
  sed -e "s|^TARGET_USER=.*|TARGET_USER=\"$TARGET_USER\"|" \
    "$SCRIPT_DIR/rc.d/S00-force-zsh.sh" > /usr/local/etc/rc.d/S00-force-zsh.sh
  chmod +x /usr/local/etc/rc.d/S00-force-zsh.sh
  echo "Installed S00-force-zsh.sh"
fi

# S00b: os-release generator (no customization needed)
cp "$SCRIPT_DIR/rc.d/S00b-generate-os-release.sh" /usr/local/etc/rc.d/
chmod +x /usr/local/etc/rc.d/S00b-generate-os-release.sh
echo "Installed S00b-generate-os-release.sh"

# S01: mount, with the chosen source dir baked in
sed -e "s|^SOURCE_DIR=.*|SOURCE_DIR=\"$SOURCE_DIR\"|" \
  "$SCRIPT_DIR/rc.d/S01-homebrew-mount.sh" > /usr/local/etc/rc.d/S01-homebrew-mount.sh
chmod +x /usr/local/etc/rc.d/S01-homebrew-mount.sh
echo "Installed S01-homebrew-mount.sh"

# S02: tailscaled, optional
if [ "$INSTALL_TAILSCALE" = "y" ]; then
  sed -e "s|^BREW_PREFIX=.*|BREW_PREFIX=\"$BREW_PREFIX\"|" \
    "$SCRIPT_DIR/rc.d/S02-tailscaled.sh" > /usr/local/etc/rc.d/S02-tailscaled.sh
  chmod +x /usr/local/etc/rc.d/S02-tailscaled.sh
  echo "Installed S02-tailscaled.sh"
  echo "(Remember: brew install tailscale, then run 'tailscale up' once manually to authenticate)"
fi

# ---------------------------------------------------------------------
# 5. Run everything once now, so the current session is fully set up
# ---------------------------------------------------------------------

echo
echo "-- Running rc.d scripts now --"
for f in /usr/local/etc/rc.d/S*.sh; do
  echo "Running $f start"
  sh "$f" start
done

echo
echo "== Done =="
echo "Reboot to confirm everything comes up automatically:"
echo "  sudo reboot"
echo "Then check:"
echo "  mount | grep /home"
echo "  cat /etc/os-release"
[ "$INSTALL_TAILSCALE" = "y" ] && echo "  ps aux | grep tailscaled"
[ -n "$TARGET_USER" ] && echo "  echo \$SHELL"
