#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
DEBIAN_ROOT="$PREFIX/var/lib/proot-distro/installed-rootfs/debian"
USER_NAME="${1:-xxlm47}"

say(){ printf '\n==> %s\n' "$*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }

[ "$(uname -m)" = "aarch64" ] || die "ARM64/aarch64 required."
command -v pkg >/dev/null || die "Run this in Termux."

say "Installing minimal Termux/X11 host"
pkg update -y
pkg install -y x11-repo proot-distro termux-x11-nightly pulseaudio dbus git curl wget

say "Installing Debian"
if ! proot-distro list | grep -A2 '^debian' | grep -q 'Installed: yes'; then
  proot-distro install debian
fi

cat > "$DEBIAN_ROOT/tmp/debian-lite-setup.sh" <<'INNER'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
USER_NAME="${USER_NAME:-xxlm47}"

apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  lxde-core lxsession lxpanel pcmanfm openbox dbus-x11 x11-xserver-utils \
  xterm mousepad sudo ca-certificates curl wget git procps psmisc nano htop

if ! id -u "$USER_NAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USER_NAME"
fi

usermod -aG sudo "$USER_NAME" || true
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USER_NAME" > "/etc/sudoers.d/90-$USER_NAME"
chmod 440 "/etc/sudoers.d/90-$USER_NAME"

HOME_DIR="/home/$USER_NAME"
mkdir -p "$HOME_DIR/Desktop" "$HOME_DIR/.config"

cat > "$HOME_DIR/.bash_profile" <<'EOF'
[ -f ~/.bashrc ] && . ~/.bashrc
export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
EOF

cat > "$HOME_DIR/.bashrc" <<'EOF'
export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
alias ll='ls -lah'
alias update='sudo apt update && sudo apt upgrade -y'
alias install='sudo apt install'
alias remove='sudo apt remove'
EOF

chown -R "$USER_NAME":"$USER_NAME" "$HOME_DIR"
echo "Debian Lite GUI installed."
INNER

sed -i "s/USER_NAME:-xxlm47/USER_NAME:-$USER_NAME/" "$DEBIAN_ROOT/tmp/debian-lite-setup.sh"
chmod +x "$DEBIAN_ROOT/tmp/debian-lite-setup.sh"
proot-distro login debian --shared-tmp -- env USER_NAME="$USER_NAME" /bin/bash /tmp/debian-lite-setup.sh
rm -f "$DEBIAN_ROOT/tmp/debian-lite-setup.sh"

cat > "$PREFIX/bin/debian-lite" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
set -e

pkill -f 'xfce4-session|startlxde|lxsession' 2>/dev/null || true
pkill -f '^termux-x11' 2>/dev/null || true

pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1 || true
pacmd load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 >/dev/null 2>&1 || true

export XDG_RUNTIME_DIR="${TMPDIR:-$PREFIX/tmp}"
mkdir -p "$XDG_RUNTIME_DIR"

termux-x11 :0 -legacy-drawing >/dev/null 2>&1 &
sleep 2
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
sleep 1

proot-distro login debian --user "${DEBIAN_USER:-xxlm47}" --shared-tmp -- \
  env DISPLAY=:0 PULSE_SERVER=127.0.0.1 XDG_RUNTIME_DIR=/tmp \
  dbus-launch --exit-with-session startlxde
LAUNCHER

chmod +x "$PREFIX/bin/debian-lite"

cat > "$PREFIX/bin/debian-lite-stop" <<'STOP'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f 'xfce4-session|startlxde|lxsession' 2>/dev/null || true
am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true
pkill -f '^termux-x11' 2>/dev/null || true
STOP
chmod +x "$PREFIX/bin/debian-lite-stop"

echo
echo "DEBIAN LITE READY"
echo "Start: debian-lite"
echo "Stop:  debian-lite-stop"
echo "RAM-first design: Debian + LXDE/Openbox + Termux:X11"
