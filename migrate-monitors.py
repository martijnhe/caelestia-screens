#!/usr/bin/env python3
"""Move hl.monitor() rules between hypr-user.lua and the file the Screens widget writes.

install-screens:    hl.monitor() blocks in hypr-user.lua move to screens-monitors.lua and
                    are replaced by one `require("screens-monitors")` line.
install-flightdeck: the rules move to the Monitors section of astra-flightdeck.lua, shared
                    with FlightDeck. Rules FlightDeck already has are kept as they are.
uninstall:          rules in screens-monitors.lua go back into hypr-user.lua where the
                    require line was. Rules shared with FlightDeck stay with FlightDeck.

A copy of the original hypr-user.lua is kept in screens-backup/.

usage: migrate-monitors.py install-screens|install-flightdeck|uninstall CAELESTIA_CONFIG_DIR
"""
import re
import shutil
import sys
from pathlib import Path

MARKER = "-- screens:monitors"
REQUIRE = f'require("screens-monitors") {MARKER} (managed by the Screens widget)'
BLOCK = re.compile(r"hl\.monitor\(\{.*?\}\)", re.S)
HEADER = "-- Written by the Caelestia Screens widget. Edit with the widget, or by hand when it's closed.\n\n"


def backup_user(conf: Path):
    user = conf / "hypr-user.lua"
    backup = conf / "screens-backup"
    backup.mkdir(exist_ok=True)
    if user.exists() and not (backup / "hypr-user.lua.orig").exists():
        shutil.copy2(user, backup / "hypr-user.lua.orig")


def install_flightdeck(conf: Path):
    user = conf / "hypr-user.lua"
    rules = conf / "screens-monitors.lua"
    shared = conf / "astra-flightdeck.lua"
    if not shared.exists():
        return install(conf)
    backup_user(conf)
    text = user.read_text() if user.exists() else ""
    if MARKER in text:
        blocks = BLOCK.findall(rules.read_text()) if rules.exists() else []
        text = "\n".join(l for l in text.split("\n") if MARKER not in l)
        if rules.exists():
            rules.rename(conf / "screens-backup" / "screens-monitors.lua.last")
    else:
        blocks = BLOCK.findall(text)
        for b in blocks:
            text = text.replace(b, "", 1)
    user.write_text(re.sub(r"\n{3,}", "\n\n", text))

    current = shared.read_text()
    if blocks and not BLOCK.search(current):
        shared.write_text(current.rstrip("\n") + "\n\n-- Monitors\n" + "\n".join(blocks) + "\n\n")
    print("Monitor rules are shared with FlightDeck in", shared)


def install(conf: Path):
    user = conf / "hypr-user.lua"
    rules = conf / "screens-monitors.lua"
    text = user.read_text() if user.exists() else ""
    if MARKER in text:
        return
    backup_user(conf)

    blocks = BLOCK.findall(text)
    if not rules.exists():
        rules.write_text(HEADER + "\n".join(blocks) + "\n")

    if blocks:
        first = text.index(blocks[0])
        for b in blocks:
            text = text.replace(b, "", 1)
        text = text[:first] + REQUIRE + text[first:]
        # Tidy the blank lines left behind
        text = re.sub(r"\n{3,}", "\n\n", text)
    else:
        text = REQUIRE + "\n\n" + text
    user.write_text(text)
    print("Moved monitor rules to", rules)


def uninstall(conf: Path):
    user = conf / "hypr-user.lua"
    rules = conf / "screens-monitors.lua"
    if not user.exists() or MARKER not in user.read_text():
        return
    blocks = BLOCK.findall(rules.read_text()) if rules.exists() else []
    lines = user.read_text().split("\n")
    out = []
    for line in lines:
        if MARKER in line:
            out.extend("\n".join(blocks).split("\n") if blocks else [])
        else:
            out.append(line)
    user.write_text("\n".join(out))
    if rules.exists():
        rules.rename(conf / "screens-backup" / "screens-monitors.lua.last")
    print("Monitor rules moved back to", user)


if __name__ == "__main__":
    actions = {"install": install, "install-screens": install, "install-flightdeck": install_flightdeck, "uninstall": uninstall}
    if len(sys.argv) != 3 or sys.argv[1] not in actions:
        sys.exit(__doc__)
    actions[sys.argv[1]](Path(sys.argv[2]).expanduser())
