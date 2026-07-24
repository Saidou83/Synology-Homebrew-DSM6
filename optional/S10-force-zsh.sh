#!/bin/sh
# S10-force-zsh.sh (OPTIONAL — not required for Homebrew itself)
#
# DSM's Package Center / User settings UI does not let you set a user's
# login shell to a Homebrew-installed zsh. DSM also has a habit of
# resetting /etc/passwd shell entries under some conditions, so this
# re-applies the desired shell on every boot.
#
# Resolves the real zsh binary rather than assuming a fixed path. This
# is more robust than a plain `which zsh`, because /usr/local/etc/rc.d/
# scripts run early in boot with a minimal PATH that may not include
# Homebrew's bin dir or community-package locations yet -- so we
# explicitly extend PATH first, then fall back to checking known
# install locations directly if `which` still finds nothing.
#
# EDIT THIS: set the username you want to switch to zsh.
TARGET_USER="your_username_here"

# Extend PATH with common zsh install locations before searching.
export PATH="/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Fixed fallback locations, checked in order, in case `which` still
# can't find it (e.g. PATH above doesn't match this system's layout).
FALLBACK_PATHS="
/home/linuxbrew/.linuxbrew/bin/zsh
/usr/local/bin/zsh
/usr/bin/zsh
/bin/zsh
"

case "$1" in
  start)
    TARGET_SHELL=$(which zsh 2>/dev/null)

    if [ -z "$TARGET_SHELL" ] || [ ! -x "$TARGET_SHELL" ]; then
      TARGET_SHELL=""
      for candidate in $FALLBACK_PATHS; do
        if [ -x "$candidate" ]; then
          TARGET_SHELL="$candidate"
          break
        fi
      done
    fi

    if [ -z "$TARGET_SHELL" ]; then
      echo "S10-force-zsh: zsh not found (checked PATH and known" >&2
      echo "install locations), skipping." >&2
      exit 0
    fi

    CURRENT_SHELL=$(awk -F: -v u="$TARGET_USER" '$1==u{print $NF}' /etc/passwd)

    if [ -z "$CURRENT_SHELL" ]; then
      echo "S10-force-zsh: user '$TARGET_USER' not found in /etc/passwd, skipping." >&2
      exit 0
    fi

    if [ "$CURRENT_SHELL" != "$TARGET_SHELL" ]; then
      sed -i.bak "$(awk -F: -v u="$TARGET_USER" '$1==u{print NR}' /etc/passwd)s|${CURRENT_SHELL}|${TARGET_SHELL}|" /etc/passwd
    fi
    ;;
  stop)
    ;;
  *)
    echo "Usage: $0 {start|stop}" >&2
    exit 1
    ;;
esac
