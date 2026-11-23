#!/usr/bin/env bash
# Unattended recording for agents: run after ../install.sh, as your normal user (asks for sudo).
# Adds a virtual mouse whose clicks Openscreen records, a screen picker agents can answer, the
# `openscreen-agent` command, and Openscreen's MCP server for Claude Code.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

BIN="$HOME/.local/bin"
UNITS="$HOME/.config/systemd/user"
XDPH_CONF="$HOME/.config/hypr/xdph.conf"

echo "==> ydotool (virtual mouse) and input access"
sudo pacman -S --needed --noconfirm ydotool jq wtype grim
sudo install -Dm644 72-openscreen-agent-input.rules /etc/udev/rules.d/72-openscreen-agent-input.rules
echo uinput | sudo tee /etc/modules-load.d/openscreen-agent-uinput.conf >/dev/null
sudo modprobe uinput
sudo udevadm control --reload-rules
sudo udevadm trigger --action=add --subsystem-match=misc --sysname-match=uinput

echo "==> openscreen-agent and the picker"
install -Dm755 openscreen-agent "$BIN/openscreen-agent"
install -Dm755 openscreen-agent-picker "$BIN/openscreen-agent-picker"
mkdir -p "$(dirname "$XDPH_CONF")"
[[ -e "$XDPH_CONF" && ! -e "$XDPH_CONF.bak" ]] && cp "$XDPH_CONF" "$XDPH_CONF.bak"
if [[ -f "$XDPH_CONF" ]] && grep -q 'custom_picker_binary' "$XDPH_CONF"; then
    sed -i "s|^\(\s*custom_picker_binary\s*=\s*\).*|\1$BIN/openscreen-agent-picker|" "$XDPH_CONF"
elif [[ -f "$XDPH_CONF" ]] && grep -q '^screencopy' "$XDPH_CONF"; then
    sed -i "/^screencopy\s*{/a\    custom_picker_binary = $BIN/openscreen-agent-picker" "$XDPH_CONF"
else
    printf 'screencopy {\n    custom_picker_binary = %s\n}\n' "$BIN/openscreen-agent-picker" >>"$XDPH_CONF"
fi

echo "==> Services"
install -Dm644 ydotool-openscreen-agent.conf "$UNITS/ydotool.service.d/openscreen-agent.conf"
systemctl --user daemon-reload
systemctl --user enable ydotool.service
systemctl --user reset-failed ydotool.service 2>/dev/null || true
systemctl --user restart ydotool.service xdg-desktop-portal-hyprland.service

if command -v claude >/dev/null; then
    echo "==> Openscreen MCP server for Claude Code"
    claude mcp remove -s user openscreen >/dev/null 2>&1 || true
    claude mcp add -s user openscreen -- "$BIN/openscreen-agent" mcp
    install -Dm644 SKILL.md "$HOME/.claude/skills/openscreen-record/SKILL.md"
fi

echo "==> Done. Try: openscreen-agent help"
