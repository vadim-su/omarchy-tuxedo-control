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
# Exactly the commands the panel issues; keep in sync with tuxctl's validate().
cmds=()
for v in high_capacity balanced stationary; do cmds+=("charging_profile $v"); done
for k in fn_lock usb_powershare ac_auto_boot; do cmds+=("$k 0" "$k 1"); done
for v in power_save enthusiast overboost; do cmds+=("perf_profile $v"); done
for v in auto quiet balanced cool max; do cmds+=("fan $v"); done
{
  printf 'Cmnd_Alias TUXCTL = '
  printf '/usr/local/bin/tuxctl set %s, ' "${cmds[@]}" | sed 's/, $//'
  printf '\n%s ALL=(root) NOPASSWD: TUXCTL\n' "$user"
} >"$sudoers.tmp"
chmod 440 "$sudoers.tmp"
visudo -cf "$sudoers.tmp" >/dev/null
mv "$sudoers.tmp" "$sudoers"

systemctl daemon-reload
systemctl enable tuxctl.service
systemctl restart tuxctl.service
echo "tuxctl installed for $user"
