#!/bin/sh
# S11-tailscaled.sh (OPTIONAL — not required for Homebrew itself)
#
# Example of running a Homebrew-installed background service at boot,
# using Tailscale as the example (requires: brew install tailscale).
#
# Starts a Homebrew-installed tailscaled at boot.
#
# Why not Package Center's native Tailscale package? If you've switched
# to the Homebrew build (e.g. for a newer version than Synology ships),
# the native package's client/daemon are incompatible with it, and its
# hardcoded socket path (/var/packages/Tailscale/etc/tailscaled.sock)
# will conflict with a Homebrew install.
#
# Why not Task Scheduler's boot-up trigger? It fires before volumes are
# guaranteed to be mounted, so a plain "boot-up" task needs a `sleep N`
# guess to work reliably -- which breaks whenever boot time varies.
# Scripts in /usr/local/etc/rc.d/ only run once the system is fully up,
# so no sleep is needed, and numbering guarantees this script (S11) runs
# after S01-homebrew-mount.sh in rc.d/ (which the Homebrew binary depends
# on — /home must be mounted before this binary path exists).
#
# EDIT THIS if your Homebrew prefix differs from the default.
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
TAILSCALED_BIN="${BREW_PREFIX}/bin/tailscaled"
STATE_DIR="${BREW_PREFIX}/var/tailscale"
STATE_FILE="${STATE_DIR}/tailscaled.state"
SOCKET="/var/run/tailscale/tailscaled.sock"
LOG_FILE="/var/log/tailscaled.log"

case "$1" in
  start)
    if [ ! -x "$TAILSCALED_BIN" ]; then
      echo "S02-tailscaled: $TAILSCALED_BIN not found, skipping." >&2
      exit 0
    fi

    mkdir -p "$(dirname "$SOCKET")"
    mkdir -p "$STATE_DIR"

    "$TAILSCALED_BIN" \
      --state="$STATE_FILE" \
      --socket="$SOCKET" \
      > "$LOG_FILE" 2>&1 &
    ;;
  stop)
    pkill -f "$TAILSCALED_BIN" 2>/dev/null || true
    ;;
  *)
    echo "Usage: $0 {start|stop}" >&2
    exit 1
    ;;
esac
