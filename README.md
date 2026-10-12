# Caelestia Screens widget

Arrange and configure monitors from the [Caelestia shell](https://github.com/caelestia-dots/shell) bar.
A remake of the Omarchy [omarchy-screens](https://github.com/IM0001GT/omarchy-screens) plugin
(MIT, by IM0001GT) for Caelestia and Hyprland's Lua config.

Built against `caelestia-shell` 2.5.0, `quickshell-git` 0.3.1 and Hyprland 0.56 (Lua config).

## Features

- **Layout**: screens drawn at their real size and position. Drag a screen and it snaps flush to a
  neighbour (no gaps, no overlaps); dropping one above or below another centres it
- **Per screen**: on/off, resolution, refresh rate, scale (presets and slider), rotation,
  mirroring, VRR (off / always / fullscreen / games & video), 8-bit / 10-bit / HDR
- **Only what the screen supports**: each screen's EDID is read with `edid-decode` and shown as
  a line like "10-bit · HDR10 up to 359 nits · BT.2020 · VRR 48–120 Hz". VRR needs a continuous
  refresh range wider than 10 Hz (the same test amdgpu uses) or AMD's FreeSync block; 10-bit needs a
  10-bit panel; HDR needs HDR10 (SMPTE ST 2084) support. Unsupported options are greyed out with the
  reason. If a screen's EDID can't be read, everything stays available
- **Brightness** per screen, live, via Caelestia's brightness service (DDC/CI or backlight)
- **Night light** with `hyprsunset`, 1500–6500 K
- **Find**: shows each screen's name and mode on that screen
- **Apply safely**: changes are drafted, then applied live with `hyprctl eval`. A
  "Keep these display settings?" card appears on every screen (Enter keeps, Escape reverts); without
  Keep everything reverts after 20 seconds. Only kept settings are written to disk. **Undo** drops the
  draft
- **Profiles**: save the current layout; Apply it later, or let **Apply on connect** restore it
  when exactly those screens are plugged in. Screens are matched by make, model and serial, so
  connector names can change
- Bar icon: two screens; the small one fills while there are unapplied changes and the icon pulses
  while waiting for Keep

## Compared with omarchy-screens

Reference: [IM0001GT/omarchy-screens](https://github.com/IM0001GT/omarchy-screens) (MIT). This is a
rewrite for Caelestia, not a copy of its code. What it covers:

| Feature in omarchy-screens | Here |
| --- | --- |
| Drag layout, flush edge snap, centre snap when stacking | Yes |
| Resolution, refresh, scale, rotation, mirror, turn a screen on/off | Yes (scale slider in 0.05 steps, not 0.01) |
| Apply with 20 s Keep / Revert, Undo | Yes |
| Brightness for the selected screen (backlight or DDC) | Yes |
| Night light, 1500–6500 K | Yes |
| Find | Yes (labels every screen, not only the selected one) |
| VRR modes; HDR/VRR disabled when the screen can't do them | Yes |
| Profiles: save, apply, restore on connect | Yes, but names are generated (no renaming) |
| HDR **Auto** (SDR desktop, HDR only for fullscreen games/video) | No: HDR is off or always on |
| HDR **Tune**: colour presets, wide-colour EDID override, SDR brightness/saturation, black floor, SDR peak | No |
| **All monitors** brightness | No |
| **Make primary** | No |
| **Detect** (rescan DRM for a screen that's off) | Partly: refresh button, and the on/off switch |
| Restore the saved layout when a screen is turned back on or mirroring is turned off | No |
| Rolling timestamped backups of the monitor rules | No: only the original `hypr-user.lua` is backed up |
| Super+/ and Super+Alt+/ scale keys | No |
| Text size | No (Omarchy-specific) |
| Spread workspaces across screens, per-screen workspace numbers | No (Omarchy bar-specific) |
| Pixel Care bar dimming | No (Omarchy bar-specific) |
| hyprmoncfg / HyprMod detection | No |
| Laptop panel (eDP) clamshell handling | Not needed on this desktop; untested on laptops |
| Not writing Hyprland's FALLBACK output | Yes |

## Requirements

`hyprctl`, `edid-decode` (from `v4l-utils`), `hyprsunset` for night light, `ddcutil` for external
screen brightness.

## Files it manages

- `~/.config/caelestia/screens-monitors.lua`: the `hl.monitor()` rules. The installer moves your
  existing rules from `hypr-user.lua` here and puts `require("screens-monitors")` in their place.
  Rules for screens that aren't connected are kept
- `~/.config/caelestia/screens.json`: profiles, night light and other settings
- `~/.config/caelestia/screens-backup/`: your original `hypr-user.lua`

## Install

```bash
./install.sh
kill $(pgrep -x qs); qs -c caelestia -n -d
```

Adds the widget to the shared widget group above the clock (see `patch.py`), like the Syncthing,
Sony, Tailscale and webcam widgets. After a `caelestia-shell` update, rebuild the user config:

```bash
rm -rf ~/.config/quickshell/caelestia
for w in syncthing sony tailscale webcam screens; do ~/Projects/caelestia-$w/install.sh; done
```

Every install checks the shared **plugins** bar section (the widget group above the clock) and
creates or repairs it if any part is missing: the group file, the two edits in `Bar.qml` (restored
from Caelestia's own copy if they were mangled), and an enabled `plugins` entry in `bar.entries`.
It ends with `Plugins bar section: OK`, or stops and says what's wrong.

## Uninstall

```bash
./uninstall.sh
```

Moves your current monitor rules back into `hypr-user.lua` and removes the widget.

## Files

| File | Purpose |
| --- | --- |
| `files/services/Displays.qml` | Singleton: monitor state, snapping, Lua rules, apply/keep/revert, profiles, night light |
| `files/modules/bar/components/status/ScreensStatus.qml` | Bar icon |
| `files/modules/bar/popouts/ScreensPopout.qml` | Popout |
| `files/modules/bar/popouts/screens/ScLayout.qml` | Drag-and-snap layout canvas |
| `files/modules/bar/popouts/screens/ScScreenSettings.qml` | Settings for the selected screen |
| `files/modules/bar/popouts/screens/ScOverlays.qml` | Find labels and Keep/Revert card on every screen |
| `migrate-monitors.py` | Moves monitor rules between `hypr-user.lua` and the widget's file |
| `patch.py` | Adds/removes the marked edits to Caelestia files |
