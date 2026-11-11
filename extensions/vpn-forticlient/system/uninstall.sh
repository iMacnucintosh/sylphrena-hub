#!/bin/bash
# Removes what system/install.sh put in place (manifest `system.uninstall`). Stops the tunnel first.
# openfortivpn itself is left installed. Run as root (the shell asks for the password).
set -euo pipefail

dst=/usr/local/sbin/sylphrena-fortivpn
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }

if [[ -x "$dst" ]]; then
  "$dst" stop || true
fi
rm -f "$dst" /etc/sudoers.d/sylphrena-fortivpn
rm -rf /run/sylphrena-fortivpn
echo "Removed $dst and its sudoers rule."
