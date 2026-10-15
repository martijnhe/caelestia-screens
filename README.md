# Caelestia Screens widget

Arrange and configure monitors from a tab in the [Caelestia shell](https://github.com/caelestia-dots/shell) dashboard.
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
- **Dashboard tab**: shown next to the other dashboard tabs; turn it on or off in Nexus > Dashboard >
  Dashboard tabs (or `dashboardTab` in `screens.json`)
- **Works with FlightDeck**: when [FlightDeck](https://github.com/AstraSuite/FlightDeck) is installed, the
  monitor rules are shared with it in `astra-flightdeck.lua`, so the two never fight over your layout, and
  the tab has an Open in FlightDeck button

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

- With FlightDeck: the `-- Monitors` section of `~/.config/caelestia/astra-flightdeck.lua`, shared with
  FlightDeck. The installer moves your `hl.monitor()` rules there from `hypr-user.lua`
- Without FlightDeck: `~/.config/caelestia/screens-monitors.lua`. The installer moves your rules there and
  puts `require("screens-monitors")` in their place in `hypr-user.lua`
- `~/.config/caelestia/display-profiles.json`: layout profiles and Apply on connect, shared with FlightDeck
  (a profile saved in either one shows up in the other)
- `~/.config/caelestia/screens.json`: night light, the tab toggle and where rules are written
- `~/.config/caelestia/screens-backup/`: your original `hypr-user.lua`

## Install

Installs into your user copy of the Caelestia shell (`~/.config/quickshell/caelestia`, created from
`/etc/xdg/quickshell/caelestia` if it doesn't exist yet). The widget's QML goes to `modules/screens/`, and
every line added to a shell file ends with `// plugin:screens`.

```bash
./install.sh               # shares monitor rules with FlightDeck when it's installed
./install.sh --standalone  # keeps its own screens-monitors.lua even with FlightDeck
kill $(pgrep -x qs); qs -c caelestia -n -d
```

Re-running `install.sh` is safe and switches between the two modes.

## Placement (optional)

With [caelestia-plugin-switcher](../caelestia-plugin-switcher) installed, this plugin can also be placed
in the dashboard's top strip instead of the right bar. Open **Nexus → Dashboard → Plugin switches**
and pick for this plugin:

- **Off**: hidden everywhere
- **Right bar**: the icon in the plugin group above the clock (default)
- **Top bar**: a tab in the dashboard, next to LocalSend and Notes

The tab is a fixed 840×480 pane with the same content as the popout.

## Uninstall

```bash
./uninstall.sh
kill $(pgrep -x qs); qs -c caelestia -n -d
```

Removes the tab and the `// plugin:screens` lines. Rules the widget owned go back into `hypr-user.lua`;
rules shared with FlightDeck stay in `astra-flightdeck.lua`.

## Files

| File | Purpose |
| --- | --- |
| `Displays.qml` | Singleton: state and actions |
| `ScreensPopout.qml` | The Screens pane shown in the dashboard tab |
| `components/` | Pane sections and small components |
| `patch.py` | Copies the QML into the shell and adds or removes the `// plugin:screens` lines |
| `migrate-monitors.py` | Moves monitor rules between `hypr-user.lua`, `screens-monitors.lua` and `astra-flightdeck.lua` |
| `install.sh` / `uninstall.sh` | Install or remove the tab |
| `manifest.json`, `BarEntry.qml`, `ScreensStatus.qml` | Entry points for shells with the plugin system ([#1703](https://github.com/caelestia-dots/shell/pull/1703)); not used by `install.sh` |
