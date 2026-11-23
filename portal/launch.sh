#!/usr/bin/env bash
# Started by systemd in place of the stock portal (see the drop-in in
# ~/.config/systemd/user/xdg-desktop-portal-hyprland.service.d/).
# Runs the patched portal when it is safe to, otherwise the stock one.

DIR="$HOME/.local/share/xdph-cursor"
BIN="$HOME/.local/libexec/xdg-desktop-portal-hyprland-cursor"
STOCK=/usr/lib/xdg-desktop-portal-hyprland
STAMP="$DIR/built-against"
ARGS=("$@")

notify() { notify-send -a "Screen sharing" -u normal "$1" "$2" 2>/dev/null || true; }

use_stock() {
    echo "xdph-cursor: $1, using stock portal" >&2
    exec "$STOCK" "${ARGS[@]}"
}

[ -x "$BIN" ] || use_stock "patched build missing"

if ldd "$BIN" 2>/dev/null | grep -q 'not found'; then
    notify "Openscreen editable cursor paused" \
        "A system update broke the patched screen-sharing portal. Run ~/.local/share/xdph-cursor/rebuild.sh"
    use_stock "missing libraries"
fi

stock_ver=$(pacman -Q xdg-desktop-portal-hyprland 2>/dev/null)
if ! grep -qxF "$stock_ver" "$STAMP" 2>/dev/null; then
    notify "Openscreen editable cursor paused" \
        "xdg-desktop-portal-hyprland was updated. Run ~/.local/share/xdph-cursor/rebuild.sh"
    use_stock "portal package updated since build"
fi

if [ "$("$DIR/deps-state.sh")" != "$(cat "$STAMP")" ]; then
    notify "Screen-sharing portal: rebuild recommended" \
        "Hyprland libraries were updated. Run ~/.local/share/xdph-cursor/rebuild.sh"
fi

start=$SECONDS
"$BIN" "$@"
rc=$?
# Crashed on startup (or quickly): fall back so screen sharing keeps working.
if [ $rc -ne 0 ]; then
    if [ $((SECONDS - start)) -lt 10 ]; then
        notify "Openscreen editable cursor paused" \
            "The patched screen-sharing portal failed to start. Run ~/.local/share/xdph-cursor/rebuild.sh"
    fi
    use_stock "patched portal exited with $rc"
fi
exit 0
