#!/bin/bash
# State of the system pieces (manifest `system.check`), run without root:
#   exit 0 installed and current, 3 installed but older than the helper in the repo, 1 missing.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
dst=/usr/local/sbin/sylphrena-fortivpn

[[ -x "$dst" ]] || exit 1
# The sudoers rule (unreadable without root): sudo lists the command as allowed without a password
sudo -n -l "$dst" >/dev/null 2>&1 || exit 1
cmp -s "$dst" "$here/../helper/sylphrena-fortivpn" || exit 3
exit 0
