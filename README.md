# openscreen-hyprland

Makes [Openscreen](https://github.com/getopenscreen/openscreen)'s **Editable cursor** and **click-based
auto-zoom** work on Hyprland (Arch / Omarchy).

Out of the box on Hyprland, Openscreen can't use Editable cursor (the portal has no "metadata" cursor
mode), and touchpad taps never count as clicks. This repo fixes both.

## What's in here

| Part | What it does |
| --- | --- |
| `portal/` | Patch for `xdg-desktop-portal-hyprland` (v1.4.1) adding the ScreenCast **metadata cursor mode**: the cursor position is sent alongside each frame instead of drawn in. Works for screen, region and window shares, scaled to buffer pixels (fractional scaling included). For windows, the pointer is placed against the window's real geometry (from Hyprland IPC), since Hyprland's own toplevel cursor positions are measured from the decorated bounding box (border/shadow). |
| `portal/launch.sh` | Started by systemd instead of the stock portal. Runs the patched build, or falls back to the stock one (with a desktop notification) when the build is outdated or broken, so screen sharing never breaks. |
| `portal/rebuild.sh` | Fetches the installed portal version, applies the patch, builds and installs to `~/.local/libexec`, restarts the portal. Run after portal/Hyprland library updates when notified. |
| `tap-bridge/` | Openscreen reads clicks straight from evdev, so libinput **taps** never reach it. This user service watches touchpads through libinput (same tap settings as Hyprland) and presses BTN_LEFT on a virtual mouse for each one- or two-finger tap. Physical presses are skipped. |
| `udev/70-openscreen-mouse.rules` | Gives the logged-in user read access to mice and touchpads (not keyboards) so Openscreen can record clicks. Includes a device-specific line for a Logitech G502 X Plus receiver, which reports itself as a keyboard too; adjust or drop it for other mice. |
| `udev/71-openscreen-tap-bridge.rules` | Sets `LIBINPUT_IGNORE_DEVICE` on the tap bridge's virtual mouse so Hyprland never acts on it (no double clicks). |
| `systemd/` | Portal drop-in and the tap bridge user service. |

Nothing under `/usr` is modified; everything lives in `~/.local` and `~/.config/systemd/user`, plus
the two udev rules in `/etc/udev/rules.d`.

## Install

```sh
./install.sh
```

Then restart Openscreen and record with Editable cursor on.

## After updates

If the portal package or its libraries update, you'll get a notification and screen sharing falls back
to stock. Run:

```sh
~/.local/share/xdph-cursor/rebuild.sh
```

If the patch no longer applies to a new portal version, it needs porting (`portal/cursor-metadata.patch`).

## Uninstall

```sh
./uninstall.sh
```

## Known limits

- Openscreen on Linux records every click as a left click (right/middle are not distinguished).
- The tap bridge can't see the keyboard, so libinput's disable-while-typing doesn't apply to it; a
  palm tap while typing may occasionally add a stray click.
- Clicks outside the recorded window don't produce zooms (nothing in frame to zoom to).
- Cursor shapes (bitmaps) aren't sent; Openscreen draws its own cursor styles.
