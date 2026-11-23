#!/usr/bin/env bash
# Remove everything install.sh set up and go back to the stock portal.
# Build dependencies are left installed; remove them yourself if nothing else needs them.
set -uo pipefail

UNITS="$HOME/.config/systemd/user"

systemctl --user disable --now openscreen-tap-bridge.service 2>/dev/null
rm -f "$UNITS/openscreen-tap-bridge.service" "$HOME/.local/libexec/openscreen-tap-bridge"
rm -rf "$HOME/.local/share/openscreen-tap-bridge"

rm -f "$UNITS/xdg-desktop-portal-hyprland.service.d/cursor-metadata.conf"
rmdir "$UNITS/xdg-desktop-portal-hyprland.service.d" 2>/dev/null
rm -f "$HOME/.local/libexec/xdg-desktop-portal-hyprland-cursor"
rm -rf "$HOME/.local/share/xdph-cursor"
systemctl --user daemon-reload
systemctl --user restart xdg-desktop-portal-hyprland.service

sudo rm -f /etc/udev/rules.d/70-openscreen-mouse.rules /etc/udev/rules.d/71-openscreen-tap-bridge.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input

echo "Removed. Screen sharing is back on the stock portal."
