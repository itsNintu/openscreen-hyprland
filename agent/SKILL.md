---
name: openscreen-record
description: Record, edit and export polished screen recordings (demo videos, walkthroughs, bug repros) with Openscreen on this Hyprland machine, fully unattended. Use when asked to record the screen or a window, make a demo/tutorial video or GIF, or show a flow on video. Covers the screen picker, clicks that trigger auto-zoom, hiding the real pointer, and exporting MP4/GIF.
---

# Unattended Openscreen recording

Openscreen (`~/Applications/Openscreen.AppImage`) records with an **editable cursor**: the pointer is
saved as data and drawn clean at export, and **left clicks become auto-zooms**. Everything here works
over SSH, with nobody at the machine.

Two interfaces, both already set up:
- **MCP server `openscreen`** (preferred): `startRecording`, `stopRecording`, `exportVideo`, `getFrames`,
  `addZoom`, `addTrim`, `addAnnotation`, `setAspectRatio`, `transcribe`… Read each tool's description.
- **`openscreen-agent`** CLI (`openscreen-agent help`): picker, pointer, input, and Openscreen's own CLI
  (`openscreen-agent record|export|sources|info`).

## Before every recording

1. **Pick what to share.** Linux always asks the desktop's picker; answer it in advance:
   `openscreen-agent pick window <title or class part>` (preferred, only that window is captured),
   `pick screen [OUTPUT]` or `pick region X,Y,W,H [OUTPUT]`. Valid 10 minutes; `unpick` afterwards.
   Without a pick, an interactive picker opens and the recording hangs until it times out.
2. **Hide the real pointer on virtual outputs** (headless boxes: `openscreen-agent where` shows outputs;
   an empty make means virtual): `openscreen-agent pointer hide`, and `pointer show` when done. Otherwise
   the real pointer is painted into the frames next to Openscreen's drawn one.
   (`openscreen-agent record` does both steps itself.)
3. **Show the content.** Only what's visible is captured. Use a free workspace
   (`openscreen-agent workspace 9`, and switch back afterwards) so other windows aren't disturbed.

## Driving the content

Use `openscreen-agent` input so the recording sees it:
- `move X Y [MS]` glides the pointer (layout pixels; `where` lists windows with positions).
- `click left [X Y]` clicks, recorded as a click: zooms land on left clicks.
- `type TEXT`, `key -M ctrl -k l -m ctrl` (wtype), `scroll N`, `screenshot` to check the screen.

Pace like a human: wait ~1 s after each result. Auto-zoom skips the first ~2.5 s and the last ~1 s, and
merges clicks less than ~3 s apart that are close on screen.

For browser automation (Playwright/CDP) that never moves the real pointer, use the MCP `setPointerTrack`
to add a cursor path and clicks afterwards.

## Example (MCP)

```
openscreen-agent workspace 9; openscreen-agent pick window "My App"; openscreen-agent pointer hide
startRecording {window: "My App"}  → drive with openscreen-agent move/click/type  → stopRecording {title}
openscreen-agent pointer show; openscreen-agent unpick; openscreen-agent workspace <previous>
exportVideo {projectId, path: "/abs/out.mp4"}   (or .gif)  → getFrames to check zooms
```

## Example (CLI only)

```
openscreen-agent record --window "My App" --duration 20 --project /tmp/demo.openscreen --json &
# drive the app…
openscreen-agent export /tmp/demo.openscreen --auto-zoom -o /tmp/demo.mp4 --json
```

Raw takes are stored in `~/.config/openscreen/recordings/`.

## If something fails

- `cursor-metadata-unsupported` or no editable cursor: the patched portal fell back to stock (usually
  after an update). Run `~/.local/share/xdph-cursor/rebuild.sh`.
- No clicks in `<video>.cursor.json`: `systemctl --user status ydotool` and check `/dev/input/event*` of
  "ydotoold virtual device" is readable by you.
- Hangs at source selection: no pick queued, or the window match failed (`openscreen-agent where`).
- Setup source: the openscreen-hyprland repo (github.com/itsNintu/openscreen-hyprland), `agent/`.
