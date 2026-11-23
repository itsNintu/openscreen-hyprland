# openscreen-hyprland

Makes [Openscreen](https://github.com/getopenscreen/openscreen)'s **Editable cursor** and **click-based
auto-zoom** work on Hyprland, without replacing Hyprland or any system package.

Tested on Arch (Omarchy) with Hyprland 0.56.2, xdg-desktop-portal-hyprland 1.4.1, Openscreen 2.3.0.

## The problems

1. **No editable cursor.** Openscreen asks the screen-sharing portal for the ScreenCast *metadata* cursor
   mode (cursor position sent alongside frames instead of drawn into them). xdg-desktop-portal-hyprland
   doesn't support it, so recording fails or falls back to a baked-in cursor.
   Upstream request: [hyprwm/xdg-desktop-portal-hyprland#444](https://github.com/hyprwm/xdg-desktop-portal-hyprland/issues/444).
2. **Touchpad taps aren't clicks.** Openscreen reads clicks straight from `/dev/input`. Taps only exist
   inside libinput/the compositor, so tap-to-click users get no click zooms.

## What this installs

| Part | What it does |
| --- | --- |
| `portal/cursor-metadata.patch` | Adds the metadata cursor mode to xdg-desktop-portal-hyprland. Works for screen, region and window shares, with fractional scaling. Frames keep flowing while only the cursor moves. |
| `portal/launch.sh` | Started by systemd in place of the stock portal. Runs the patched build, or the stock one (with a notification) if the build is outdated or broken, so screen sharing never breaks. |
| `portal/rebuild.sh` | Fetches the installed portal version, applies the patch, builds into `~/.local/libexec`, restarts the portal. |
| `tap-bridge/` | User service: watches touchpads through libinput (same tap settings as Hyprland) and clicks a virtual mouse for each one- or two-finger tap. Physical presses are skipped. |
| `udev/70-openscreen-mouse.rules` | Read access to mice and touchpads (not keyboards) for the logged-in user, so Openscreen can see clicks. The last line is for a Logitech G502 X Plus receiver, which also reports itself as a keyboard; replace or drop it for your mouse. |
| `udev/71-openscreen-tap-bridge.rules` | Hides the tap bridge's virtual mouse from Hyprland (`LIBINPUT_IGNORE_DEVICE`), so there are no double clicks. |

Everything lives in `~/.local` and `~/.config/systemd/user`, plus the two udev rules. Hyprland and the
portal package stay stock and keep updating normally.

```sh
./install.sh      # then restart Openscreen and record with Editable cursor on
./uninstall.sh    # back to the stock portal
```

After a portal or library update you'll get a notification and screen sharing falls back to stock until
you run `~/.local/share/xdph-cursor/rebuild.sh`.

## What's a workaround, and the clean fix

The portal patch itself uses the standard `ext-image-copy-capture` cursor sessions. One part works around
a Hyprland bug: the protocol says cursor positions are *buffer pixels relative to the captured buffer*,
but Hyprland 0.56 sends *logical pixels relative to the source's logical box*, which for windows includes
the border and shadow. So the patch follows the pointer per monitor, and for **window** recordings asks
Hyprland's IPC where the window is (at most every 100 ms while the pointer moves).

`upstream/hyprland-cursor-session.diff` is a proposed Hyprland fix (not compiled or tested; offered as a
starting point). With it, window shares could use a toplevel cursor session directly and the IPC lookup
goes away. Openscreen detecting taps itself would make the tap bridge unnecessary.

## Known limits

- Openscreen on Linux records every click as a left click.
- The tap bridge can't see the keyboard, so libinput's disable-while-typing doesn't apply to it; a palm tap
  while typing may occasionally add a stray click.
- No cursor bitmap is sent; Openscreen draws its own cursor styles.
- Rotated monitors are untested.
