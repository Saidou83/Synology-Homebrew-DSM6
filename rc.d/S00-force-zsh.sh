#!/bin/sh
# S00-force-zsh.sh
#
# DSM's Package Center / User settings UI does not let you set a user's
# login shell to a Homebrew-installed zsh. DSM also has a habit of
# resetting /etc/passwd shell entries under some conditions, so this
# re-applies the desired shell on every boot.
#
# Requires /bin/zsh to exist -- on DSM 6 this is usually a symlink to
# the real binary (e.g. /usr/local/bin/zsh if installed via a community
# package, or a path under your Homebrew prefix). Check with:
#   ls -la /bin/zsh
# and create the symlink first if it's missing:
#   sudo ln -s /usr/local/bin/zsh /bin/zsh
#
# EDIT THIS: set the username you want to switch to zsh.
TARGET_USER="your_username_here"
TARGET_SHELL="/bin/zsh"

case "$1" in
  start)
    if [ ! -x "$TARGET_SHELL" ]; then
      echo "S00-force-zsh: $TARGET_SHELL not found or not executable, skipping." >&2
      exit 0
    fi

    CURRENT_SHELL=$(awk -F: -v u="$TARGET_USER" '$1==u{print $NF}' /etc/passwd)

    if [ -z "$CURRENT_SHELL" ]; then
      echo "S00-force-zsh: user '$TARGET_USER' not found in /etc/passwd, skipping." >&2
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
