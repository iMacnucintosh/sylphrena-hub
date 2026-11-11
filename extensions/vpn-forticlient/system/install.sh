#!/bin/bash
# System pieces of the vpn-forticlient extension (manifest `system.install`). Run as root by the
# shell when the extension is installed from Nexus → Extensions (it asks for the password there),
# or by hand: sudo bash extensions/vpn-forticlient/system/install.sh
#
# - openfortivpn, if missing (pacman only)
# - /usr/local/sbin/sylphrena-fortivpn: a root-owned copy of ../helper/sylphrena-fortivpn, so later
#   edits of the repo never change what runs as root
# - /etc/sudoers.d/sylphrena-fortivpn: the calling user may run only that file without a password
set -euo pipefail

here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
dst=/usr/local/sbin/sylphrena-fortivpn
rule=/etc/sudoers.d/sylphrena-fortivpn
owner="${SUDO_USER:-}"

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }
[[ -n "$owner" && "$owner" != root ]] || { echo "Run through sudo from your user account." >&2; exit 1; }

if ! command -v openfortivpn >/dev/null 2>&1; then
  if command -v pacman >/dev/null 2>&1; then
    echo "Installing openfortivpn…"
    pacman -S --needed --noconfirm openfortivpn
  else
    echo "openfortivpn is not installed: install it with your package manager." >&2
    exit 2
  fi
fi

install -o root -g root -m 0755 "$here/../helper/sylphrena-fortivpn" "$dst"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s ALL=(root) NOPASSWD: %s\n' "$owner" "$dst" >"$tmp"
visudo -cqf "$tmp" || { echo "The sudoers rule did not validate; not installed." >&2; exit 1; }
install -o root -g root -m 0440 "$tmp" "$rule"
echo "Installed $dst and $rule (for $owner)."
