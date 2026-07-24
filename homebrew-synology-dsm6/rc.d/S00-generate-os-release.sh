#!/bin/sh
# S00b-generate-os-release.sh
#
# DSM does not ship /etc/os-release, which some tools (including
# Homebrew's brew.sh) try to source for OS detection. Without it you'll
# see warnings like:
#   /etc/os-release: No such file or directory
#
# This regenerates /etc/os-release on every boot using DSM's own
# version file (/etc.defaults/VERSION), so it always reflects your
# actual DSM version/build -- including after DSM updates -- without
# needing to hardcode or manually update anything.
#
# Deliberately does NOT set ID_LIKE=debian/ubuntu/etc. Doing so could
# cause Homebrew (or other tools) to assume compatibility with a distro
# family it isn't actually compatible with, and try to pull prebuilt
# binaries (bottles) built against a different glibc/libc layout than
# DSM's, which can cause obscure failures. ID=synology is intentional.

case "$1" in
  start)
    if [ ! -f /etc.defaults/VERSION ]; then
      echo "S00b-generate-os-release: /etc.defaults/VERSION not found, skipping." >&2
      exit 0
    fi

    # shellcheck disable=SC1091
    . /etc.defaults/VERSION

    cat > /etc/os-release << OSREL
NAME="Synology DSM"
ID=synology
VERSION_ID="${productversion}"
VERSION="${productversion}-${buildnumber} Update ${smallfixnumber}"
PRETTY_NAME="Synology DSM ${productversion}-${buildnumber} Update ${smallfixnumber}"
OSREL

    chmod 644 /etc/os-release
    ;;
  stop)
    ;;
  *)
    echo "Usage: $0 {start|stop}" >&2
    exit 1
    ;;
esac
