#!/bin/bash
# Install the root side of kosto.tuxedo. Run: sudo ./install.sh [user]   (or pkexec)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
user=${1:-${SUDO_USER:-$(id -nu "${PKEXEC_UID:-}" 2>/dev/null)}}
[[ $user =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "pass the desktop user name" >&2; exit 1; }
here=$(dirname "$(readlink -f "$0")")

install -Dm755 -o root -g root "$here/tuxctl" /usr/local/bin/tuxctl
install -Dm644 "$here/tuxctl.service" /etc/systemd/system/tuxctl.service
sudoers=/etc/sudoers.d/tuxctl
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/tuxctl set *\n' "$user" >"$sudoers.tmp"
chmod 440 "$sudoers.tmp"
visudo -cf "$sudoers.tmp" >/dev/null
mv "$sudoers.tmp" "$sudoers"

systemctl daemon-reload
systemctl enable tuxctl.service
systemctl restart tuxctl.service
echo "tuxctl installed for $user"
