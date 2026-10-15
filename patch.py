#!/usr/bin/env python3
"""Add or remove the Screens widget in a user copy of the Caelestia shell config.

The widget's QML goes to modules/screens/ and its service to services/Displays.qml. It can
show as a dashboard tab or as an icon in the bar's plugin group above the clock (created
here if no other caelestia-* widget made it); the pane's "Show in" buttons pick which, so
caelestia-plugin-switcher is optional.

Every line this script inserts into a shell file ends with `// plugin:screens` (or
`// plugin:host` for the shared bar group, with replaced lines kept as base64 after
`was:`), so `revert` removes exactly those lines and leaves other widgets' edits alone.

usage: patch.py apply|revert CONFIG_DIR [SHELL_JSON]
"""
import base64
import json
import re
import shutil
import sys
from pathlib import Path

NAME = "screens"
HOST = "host"
MODULE = "modules/screens"
SOURCES = ["ScreensPopout.qml", "components"]
SERVICE = "services/Displays.qml"
STATUS = "modules/bar/components/status/ScreensStatus.qml"
BAR_POPOUT = "modules/bar/popouts/ScreensPopout.qml"
OLD_BAR_COMPONENTS = "modules/bar/popouts/screens"
HOST_FILE = "modules/bar/components/PluginIcons.qml"
BAR_CONTENT = "modules/bar/popouts/Content.qml"
SLOTS = ["syncthing", "sony", "tailscale", "webcam", "screens"]

TAB_ENTRY = """\
        allTabs.push({
            component: screensTabComponent,
            iconName: "desktop_windows",
            text: qsTr("Screens"),
            enabled: Displays.settings.placement === "top"
        });"""

TAB_COMPONENT = """\
            Component {
                id: screensTabComponent

                Flickable {
                    implicitWidth: 840
                    implicitHeight: 480
                    contentWidth: width
                    contentHeight: screensPane.implicitHeight
                    clip: true

                    ScreensPopout {
                        id: screensPane

                        x: Math.max(0, (parent.width - width) / 2)
                    }
                }
            }
"""

TAB_TOGGLE = """\
                    IconButton {
                        icon: "desktop_windows"
                        type: Displays.settings.placement === "top" ? ButtonBase.Tonal : ButtonBase.Text
                        onClicked: Displays.setPlacement(Displays.settings.placement === "top" ? "off" : "top")
                    }"""

IMPORT = "import qs.modules.screens"

# The right-bar popout is the same pane as the dashboard tab
BAR_POPOUT_QML = """import QtQuick
import qs.modules.screens as Screens

// Right-bar popout for the Screens widget: the same pane as the dashboard tab.
// Written by caelestia-screens' patch.py.
Screens.ScreensPopout {
    required property PopoutState popouts
}
"""

ENTRY = """\
        Entry {
            name: "screens"

            ScreensStatus {
                colour: root.colour
            }
        }"""

POPOUT = """\
        Popout {
            name: "screens"
            sourceComponent: ScreensPopout {
                popouts: root.popouts
            }
        }
"""

# (file, anchor line (stripped prefix), offset from anchor, text, required)
INSERTS = [
    ("modules/ServiceLoader.qml", "Weather.reload();", 1, "        Displays;", True),
    ("modules/dashboard/Content.qml", "import qs.services", 1, IMPORT, True),
    ("modules/dashboard/Content.qml", "return allTabs.filter", 0, TAB_ENTRY, True),
    ("modules/dashboard/Content.qml", "Behavior on contentX {", 0, TAB_COMPONENT, True),
    ("modules/nexus/pages/panels/DashboardPanel.qml",
     "onClicked: GlobalConfig.dashboard[tabToggle.modelData.key] = !tabToggle.isOn", 3, TAB_TOGGLE, False),
]
BAR_FILES = [HOST_FILE, BAR_CONTENT]

# ---- the shared plugin group in the bar, used by every caelestia-* widget ----

HOST_QML = """pragma ComponentBehavior: Bound

// Bar group for the caelestia-* widgets, shown above the clock. Created by the
// first widget installer and removed with the last one. Each widget adds its
// icon after its slot line.

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.bar.components.status

StyledRect {
    id: root

    property color colour: Colours.palette.m3secondary
    readonly property alias items: iconColumn

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    clip: true
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: iconColumn.implicitHeight + Tokens.padding.medium * 2

    ColumnLayout {
        id: iconColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.medium

%SLOTS%
    }

    component Entry: Item {
        required property string name
        default property Item item

        Layout.alignment: Qt.AlignHCenter
        // Widgets can opt out of the bar with a `hidden` property (e.g. Sony when disconnected)
        visible: !(item?.hidden ?? false)
        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item
    }
}
""".replace("%SLOTS%", "\n".join(f"        // slot:{s}" for s in SLOTS + ["end"]))

HOST_DELEGATE = """\
            DelegateChoice {
                roleValue: "plugins"
                delegate: EntryWrapper {
                    PluginIcons {
                        objectName: "taskbarPlugins"
                    }
                }
            }"""

HOST_INSERTS = [
    ("modules/bar/Bar.qml", 'roleValue: "statusIcons"', -1, HOST_DELEGATE),
]

HOST_REPLACES = [
    ("modules/bar/Bar.qml",
     'if (id === "statusIcons" && Config.bar.popouts.statusIcons) {',
     'if ((id === "statusIcons" || id === "plugins") && Config.bar.popouts.statusIcons) {'),
    ("modules/bar/Bar.qml",
     "const items = (ch.item as StatusIcons).items;",
     'const items = id === "plugins" ? (ch.item as PluginIcons).items : (ch.item as StatusIcons).items;'),
]


def marker(name=NAME):
    return f"// plugin:{name}"


def revert_file(path: Path, name=NAME):
    if not path.exists():
        return
    out = []
    for line in path.read_text().split("\n"):
        if f"{marker(name)} was:" in line:
            indent = line[: len(line) - len(line.lstrip())]
            out.append(indent + base64.b64decode(line.split(f"{marker(name)} was:", 1)[1].strip()).decode())
        elif not line.rstrip().endswith(marker(name)):
            out.append(line)
    path.write_text("\n".join(out))


def find_line(lines, anchor):
    hits = [i for i, l in enumerate(lines) if l.strip().startswith(anchor)]
    return hits[0] if len(hits) == 1 else None


def insert(root: Path, rel, anchor, offset, text, required, name=NAME):
    path = root / rel
    if not path.exists():
        if required:
            sys.exit(f"patch failed: {rel} not found")
        return False
    lines = path.read_text().split("\n")
    at = find_line(lines, anchor)
    if at is None:
        if required:
            sys.exit(f"patch failed: {rel}: anchor {anchor!r} not found once (Caelestia changed?)")
        return False
    new = [f"{l} {marker(name)}" if l.strip() else f"{' ' * 8}{marker(name)}" for l in text.rstrip("\n").split("\n")]
    if text.endswith("\n"):
        new.append(f"{' ' * 8}{marker(name)}")
    lines[at + offset:at + offset] = new
    path.write_text("\n".join(lines))
    return True


def replace(root: Path, rel, old, new, name):
    path = root / rel
    lines = path.read_text().split("\n")
    i = find_line(lines, old)
    if i is None:
        return False
    indent = lines[i][: len(lines[i]) - len(lines[i].lstrip())]
    encoded = base64.b64encode(lines[i].strip().encode()).decode()
    lines[i] = f"{indent}{new} {marker(name)} was:{encoded}"
    path.write_text("\n".join(lines))
    return True


def strip_imports(text: str) -> str:
    text = text.replace("import martijnhe.screens.components", "import qs.modules.screens.components")
    # Displays comes from qs.services, which every file already imports
    return re.sub(r"^import martijnhe\.screens\n", "", text, flags=re.M)


def copy_sources(src: Path, root: Path):
    dest = root / MODULE
    shutil.rmtree(dest, ignore_errors=True)
    dest.mkdir(parents=True)
    for name in SOURCES:
        item = src / name
        if item.is_dir():
            shutil.copytree(item, dest / name)
        else:
            shutil.copy2(item, dest / name)
    for qml in dest.rglob("*.qml"):
        qml.write_text(strip_imports(qml.read_text()))

    text = (src / "Displays.qml").read_text()
    # The overlays are loaded by URL; importing the components here would be an import cycle
    text = re.sub(r"^import martijnhe\.screens\.components\n", "", text, flags=re.M)
    text = text.replace('Qt.resolvedUrl("components/ScOverlays.qml")', 'Qt.resolvedUrl("../modules/screens/components/ScOverlays.qml")')
    (root / SERVICE).write_text(text)


def switcher_owns_tab(root: Path):
    """True when caelestia-plugin-switcher already provides the Screens tab (unmarked lines)."""
    path = root / "modules/dashboard/Content.qml"
    return path.exists() and any(
        l.strip() == "id: screensTabComponent" and not l.rstrip().endswith(marker())
        for l in path.read_text().split("\n"))


def update_shell_json(path: Path, add: bool):
    if not path or not path.exists():
        return
    data = json.loads(path.read_text())
    bar = data.setdefault("bar", {})
    entries = bar.get("entries") or []
    has = any(e.get("id") == "plugins" for e in entries)
    if add and not has:
        ids = [e.get("id") for e in entries]
        entries.insert(ids.index("clock") if "clock" in ids else len(entries), {"id": "plugins", "enabled": True})
    elif not add and has:
        entries = [e for e in entries if e.get("id") != "plugins"]
    bar["entries"] = entries
    path.write_text(json.dumps(data, indent=4))


def create_host(root: Path, shell_json):
    """Make the bar's plugin group when no other caelestia-* widget has. False if the bar
    doesn't look like the one this was written for."""
    bar = (root / "modules/bar/Bar.qml").read_text().split("\n")
    anchors = [a for _, a, *_ in HOST_INSERTS] + [o for _, o, _ in HOST_REPLACES]
    if any(find_line(bar, a) is None for a in anchors):
        return False
    (root / HOST_FILE).write_text(HOST_QML)
    for rel, anchor, offset, text in HOST_INSERTS:
        insert(root, rel, anchor, offset, text, True, HOST)
    for rel, old, new in HOST_REPLACES:
        replace(root, rel, old, new, HOST)
    update_shell_json(shell_json, True)
    print("Added the plugin group to the bar (above the clock)")
    return True


def host_in_use(root: Path):
    """Another widget (or the plugin switcher) still has lines in the group file."""
    host = root / HOST_FILE
    return host.exists() and any(
        "// plugin:" in l and marker(HOST) not in l and marker() not in l for l in host.read_text().split("\n"))


def install_bar(src: Path, root: Path, shell_json):
    status = root / STATUS
    status.parent.mkdir(parents=True, exist_ok=True)
    status.write_text(strip_imports((src / "ScreensStatus.qml").read_text()))
    (root / BAR_POPOUT).write_text(BAR_POPOUT_QML)
    # Components of the old right-bar copy; the popout now uses modules/screens
    shutil.rmtree(root / OLD_BAR_COMPONENTS, ignore_errors=True)

    if not (root / HOST_FILE).exists() and not create_host(root, shell_json):
        print("Note: couldn't add the plugin group to this bar; Right bar placement won't show an icon")
        return
    host = (root / HOST_FILE).read_text().split("\n")
    slot = "// slot:screens" if find_line(host, "// slot:screens") is not None else "// slot:end"
    insert(root, HOST_FILE, slot, 1 if slot == "// slot:screens" else 0, ENTRY, True)
    insert(root, BAR_CONTENT, 'name: "kblayout"', -1, POPOUT, True)


def apply(src: Path, root: Path, shell_json):
    copy_sources(src, root)
    for rel in {f for f, *_ in INSERTS} | set(BAR_FILES):
        revert_file(root / rel)
    inserts = INSERTS
    if switcher_owns_tab(root):
        # The switcher's tab uses the bar popouts ScreensPopout; adding ours (and the
        # qs.modules.screens import, which shadows it) breaks the dashboard.
        inserts = [i for i in INSERTS if i[0] == "modules/ServiceLoader.qml"]
        print("Plugin switcher manages the Screens tab; leaving the dashboard files alone")
    toggle = True
    for rel, anchor, offset, text, required in inserts:
        done = insert(root, rel, anchor, offset, text, required)
        toggle = toggle and (done or required)
    if not toggle and inserts is INSERTS:
        print("Note: Nexus has no dashboard tab toggles here; use Show in on the Screens pane")
    install_bar(src, root, shell_json)


def revert(root: Path, shell_json):
    for rel in {f for f, *_ in INSERTS} | set(BAR_FILES):
        revert_file(root / rel)
    shutil.rmtree(root / MODULE, ignore_errors=True)
    for rel in (SERVICE, STATUS, BAR_POPOUT):
        (root / rel).unlink(missing_ok=True)
    shutil.rmtree(root / OLD_BAR_COMPONENTS, ignore_errors=True)
    if (root / HOST_FILE).exists() and not host_in_use(root):
        for rel in {f for f, *_ in HOST_INSERTS} | {f for f, *_ in HOST_REPLACES}:
            revert_file(root / rel, HOST)
        (root / HOST_FILE).unlink()
        update_shell_json(shell_json, False)
        print("Removed the bar's plugin group (no other widget uses it)")


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4) or sys.argv[1] not in ("apply", "revert"):
        sys.exit(__doc__)
    root = Path(sys.argv[2])
    shell_json = Path(sys.argv[3]) if len(sys.argv) == 4 else None
    if sys.argv[1] == "apply":
        apply(Path(__file__).resolve().parent, root, shell_json)
    else:
        revert(root, shell_json)
