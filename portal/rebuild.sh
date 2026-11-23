#!/usr/bin/env bash
# Rebuild the patched xdg-desktop-portal-hyprland (adds "metadata" cursor mode,
# needed for Openscreen's Editable cursor) against the installed stock version.
# Usage: ~/.local/share/xdph-cursor/rebuild.sh
set -euo pipefail

DIR="$HOME/.local/share/xdph-cursor"
PATCH="$DIR/cursor-metadata.patch"
BIN="$HOME/.local/libexec/xdg-desktop-portal-hyprland-cursor"
STAMP="$DIR/built-against"

ver=$(pacman -Q xdg-desktop-portal-hyprland | awk '{print $2}' | sed 's/-[0-9]*$//')
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "==> Fetching xdg-desktop-portal-hyprland v$ver"
git -c advice.detachedHead=false clone -q --depth 1 --branch "v$ver" https://github.com/hyprwm/xdg-desktop-portal-hyprland "$work/src"
cd "$work/src"

echo "==> Applying cursor-metadata patch"
if ! git apply -p1 "$PATCH"; then
    echo "!! The patch no longer applies to v$ver. Screen sharing keeps using the stock portal." >&2
    echo "!! The patch needs updating for this version (ask Claude)." >&2
    exit 1
fi

echo "==> Building"
meson setup build --prefix=/usr --libexecdir=lib -Dbuildtype=release >/dev/null
ninja -C build >/dev/null

install -Dm755 build/src/xdg-desktop-portal-hyprland "$BIN.new"
mv -f "$BIN.new" "$BIN"
"$DIR/deps-state.sh" > "$STAMP"

echo "==> Installed $BIN (v$ver + cursor metadata)"
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    systemctl --user restart xdg-desktop-portal-hyprland.service
    echo "==> Portal restarted"
fi
