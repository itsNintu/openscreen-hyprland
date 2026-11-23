#!/usr/bin/env bash
# Install everything: patched portal (editable cursor), tap bridge (taps as clicks), udev rules.
# Run from a Hyprland session as your normal user; asks for sudo once for the udev rules.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

XDPH_DIR="$HOME/.local/share/xdph-cursor"
TAP_DIR="$HOME/.local/share/openscreen-tap-bridge"
LIBEXEC="$HOME/.local/libexec"
UNITS="$HOME/.config/systemd/user"

echo "==> Build dependencies"
sudo pacman -S --needed --noconfirm base-devel git meson ninja hyprwayland-scanner hyprland-protocols \
    wayland-protocols libinput systemd-libs

echo "==> udev rules (mouse/touchpad read access for Openscreen, hide the tap bridge from Hyprland)"
sudo install -Dm644 udev/70-openscreen-mouse.rules /etc/udev/rules.d/70-openscreen-mouse.rules
sudo install -Dm644 udev/71-openscreen-tap-bridge.rules /etc/udev/rules.d/71-openscreen-tap-bridge.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input

echo "==> Patched portal"
install -Dm644 portal/cursor-metadata.patch "$XDPH_DIR/cursor-metadata.patch"
install -Dm755 portal/rebuild.sh "$XDPH_DIR/rebuild.sh"
install -Dm755 portal/launch.sh "$XDPH_DIR/launch.sh"
install -Dm755 portal/deps-state.sh "$XDPH_DIR/deps-state.sh"
install -Dm644 systemd/xdph-cursor-metadata.conf "$UNITS/xdg-desktop-portal-hyprland.service.d/cursor-metadata.conf"
systemctl --user daemon-reload
"$XDPH_DIR/rebuild.sh"

# The tap bridge only matters on machines with a touchpad (skip with NO_TAP_BRIDGE=1).
if [[ -z "${NO_TAP_BRIDGE:-}" ]] && udevadm info --export-db | grep -q '^E: ID_INPUT_TOUCHPAD=1'; then
    echo "==> Tap bridge"
    install -Dm644 tap-bridge/tap-bridge.c "$TAP_DIR/tap-bridge.c"
    mkdir -p "$LIBEXEC"
    gcc -O2 -Wall -o "$LIBEXEC/openscreen-tap-bridge" "$TAP_DIR/tap-bridge.c" $(pkg-config --cflags --libs libinput libudev)
    install -Dm644 systemd/openscreen-tap-bridge.service "$UNITS/openscreen-tap-bridge.service"
    systemctl --user daemon-reload
    systemctl --user enable --now openscreen-tap-bridge.service
else
    echo "==> No touchpad found, skipping the tap bridge"
fi

echo "==> Done. Restart Openscreen, then record with Editable cursor on."
