#!/usr/bin/env python3
"""Add or remove the Screens dashboard tab in a user copy of the Caelestia shell config.

The widget's QML goes to modules/screens/. Every line this script inserts into a
shell file ends with `// plugin:screens`, so `revert` removes exactly those lines
and leaves other widgets' edits alone.

usage: patch.py apply|revert CONFIG_DIR
"""
import re
import shutil
import sys
from pathlib import Path

NAME = "screens"
MODULE = "modules/screens"
SOURCES = ["Displays.qml", "ScreensPopout.qml", "components"]

TAB_ENTRY = """\
        allTabs.push({
            component: screensTabComponent,
            iconName: "desktop_windows",
            text: qsTr("Screens"),
            enabled: Displays.settings.dashboardTab
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
                        type: Displays.settings.dashboardTab ? ButtonBase.Tonal : ButtonBase.Text
                        onClicked: Displays.settings.dashboardTab = !Displays.settings.dashboardTab
                    }"""

IMPORT = "import qs.modules.screens"

# (file, anchor line (stripped prefix), offset from anchor, text, required)
INSERTS = [
    ("modules/ServiceLoader.qml", "import qs.services", 1, IMPORT, True),
    ("modules/ServiceLoader.qml", "Weather.reload();", 1, "        Displays;", True),
    ("modules/dashboard/Content.qml", "import qs.services", 1, IMPORT, True),
    ("modules/dashboard/Content.qml", "return allTabs.filter", 0, TAB_ENTRY, True),
    ("modules/dashboard/Content.qml", "Behavior on contentX {", 0, TAB_COMPONENT, True),
    ("modules/nexus/pages/panels/DashboardPanel.qml", "import qs.services", 1, IMPORT, False),
    ("modules/nexus/pages/panels/DashboardPanel.qml",
     "onClicked: GlobalConfig.dashboard[tabToggle.modelData.key] = !tabToggle.isOn", 3, TAB_TOGGLE, False),
]


def marker():
    return f"// plugin:{NAME}"


def revert_file(path: Path):
    if not path.exists():
        return
    lines = path.read_text().split("\n")
    path.write_text("\n".join(l for l in lines if not l.rstrip().endswith(marker())))


def find_line(lines, anchor):
    hits = [i for i, l in enumerate(lines) if l.strip().startswith(anchor)]
    return hits[0] if len(hits) == 1 else None


def insert(root: Path, rel, anchor, offset, text, required):
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
    new = [f"{l} {marker()}" if l.strip() else f"{' ' * 8}{marker()}" for l in text.rstrip("\n").split("\n")]
    if text.endswith("\n"):
        new.append(f"{' ' * 8}{marker()}")
    lines[at + offset:at + offset] = new
    path.write_text("\n".join(lines))
    return True


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
        text = qml.read_text()
        text = text.replace("import martijnhe.screens.components", "import qs.modules.screens.components")
        if qml.parent == dest:
            text = re.sub(r"^import martijnhe\.screens\n", "", text, flags=re.M)
        else:
            text = text.replace("import martijnhe.screens\n", "import qs.modules.screens\n")
        qml.write_text(text)


def switcher_owns_tab(root: Path):
    """True when caelestia-plugin-switcher already provides the Screens tab (unmarked lines)."""
    path = root / "modules/dashboard/Content.qml"
    return path.exists() and any(
        l.strip() == "id: screensTabComponent" and not l.rstrip().endswith(marker())
        for l in path.read_text().split("\n"))


def apply(src: Path, root: Path):
    copy_sources(src, root)
    for rel in {f for f, *_ in INSERTS}:
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
        print("Note: Nexus has no dashboard tab toggles here; turn the tab on or off with dashboardTab in screens.json")


def revert(root: Path):
    for rel in {f for f, *_ in INSERTS}:
        revert_file(root / rel)
    shutil.rmtree(root / MODULE, ignore_errors=True)


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("apply", "revert"):
        sys.exit(__doc__)
    root = Path(sys.argv[2])
    if sys.argv[1] == "apply":
        apply(Path(__file__).resolve().parent, root)
    else:
        revert(root)
