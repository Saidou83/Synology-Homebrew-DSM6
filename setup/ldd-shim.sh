#!/bin/sh
# ldd-shim.sh
#
# DSM does not ship an `ldd` command, but Homebrew's install script calls
# `ldd --version` to check the system's glibc version before deciding
# whether it can install a portable Ruby. Without this shim, the installer
# fails even though DSM's glibc (in /usr/lib/libc.so.6) is new enough.
#
# This creates a fake /usr/bin/ldd that reads the *real* glibc version
# directly from libc.so.6, so the check reflects your actual system
# instead of a hardcoded number.
#
# Run this ONCE, before running the official Homebrew install script
# from https://brew.sh.
#
# Usage:
#   sudo sh setup/ldd-shim.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

cat > /usr/bin/ldd << 'EOF'
#!/bin/bash
[[ $(/usr/lib/libc.so.6) =~ version\ ([0-9]\.[0-9]+) ]]
echo "ldd ${BASH_REMATCH[1]}"
EOF

chmod +x /usr/bin/ldd

echo "Created /usr/bin/ldd shim:"
/usr/bin/ldd
