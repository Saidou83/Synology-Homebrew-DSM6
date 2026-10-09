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
SETSID_BIN="${BREW_PREFIX}/bin/setsid"
STATE_DIR="${BREW_PREFIX}/var/tailscale"
STATE_FILE="${STATE_DIR}/tailscaled.state"
SOCKET="/var/run/tailscale/tailscaled.sock"
LOG_FILE="/var/log/tailscaled.log"
LOG_MAX_KB=5120   # rotate at ~5 MB; keeps one old copy (.1)

log() {
  echo "$(date '+%Y/%m/%d %H:%M:%S') S11-tailscaled: $*" >> "$LOG_FILE"
}

# copy+truncate (not mv): the daemon keeps its fd open, and since the
# file is opened with >> (O_APPEND), truncating it in place is safe.
rotate_log() {
  [ -f "$LOG_FILE" ] || return 0
  if [ "$(du -k "$LOG_FILE" | cut -f1)" -gt "$LOG_MAX_KB" ]; then
    cp "$LOG_FILE" "${LOG_FILE}.1" && : > "$LOG_FILE"
  fi
}

case "$1" in
  start)
    if [ ! -x "$TAILSCALED_BIN" ]; then
      echo "S11-tailscaled: $TAILSCALED_BIN not found, skipping." >&2
      exit 0
    fi

    rotate_log

    if pgrep -f "$TAILSCALED_BIN" > /dev/null 2>&1; then
      echo "S11-tailscaled: already running, skipping."
      exit 0
    fi

    mkdir -p "$(dirname "$SOCKET")"
    mkdir -p "$STATE_DIR"

    # Detach from any controlling terminal so a manual start over SSH
    # survives logout (SIGHUP). setsid comes from Homebrew's util-linux.
    if [ -x "$SETSID_BIN" ]; then DETACH="$SETSID_BIN"; else DETACH="nohup"; fi

    log "tailscaled not running, starting it"
    $DETACH "$TAILSCALED_BIN" \
      --state="$STATE_FILE" \
      --socket="$SOCKET" \
      < /dev/null >> "$LOG_FILE" 2>&1 &
    ;;
  stop)
    pgrep -f "$TAILSCALED_BIN" > /dev/null 2>&1 || exit 0
    log "stopping tailscaled"
    pkill -f "$TAILSCALED_BIN" 2>/dev/null
    # Wait for a clean exit (it tears down routes/iptables), max 15s.
    i=0
    while pgrep -f "$TAILSCALED_BIN" > /dev/null 2>&1; do
      i=$((i + 1))
      if [ "$i" -ge 15 ]; then
        log "still running after 15s, sending SIGKILL"
        pkill -9 -f "$TAILSCALED_BIN" 2>/dev/null
        sleep 1
        break
      fi
      sleep 1
    done
    ;;
  restart)
    sh "$0" stop
    sh "$0" start
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}" >&2
    exit 1
    ;;
esac
