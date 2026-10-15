#!/bin/bash
# Install the Screens widget as a dashboard tab in a user copy of the Caelestia shell config.
# Safe to re-run. With FlightDeck installed, monitor rules are shared with FlightDeck
# (~/.config/caelestia/astra-flightdeck.lua); without it the widget keeps its own
# ~/.config/caelestia/screens-monitors.lua.
#   --standalone   keep the widget's own rules file even when FlightDeck is installed
set -euo pipefail

src=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
system=/etc/xdg/quickshell/caelestia
conf=${XDG_CONFIG_HOME:-$HOME/.config}
target=$conf/quickshell/caelestia

if [[ ! -e $target ]]; then
  [[ -d $system ]] || { echo "caelestia-shell not found at $system" >&2; exit 1; }
  echo "Creating user copy of the Caelestia config at $target"
  cp -r -- "$system" "$target"
fi

mode=screens
if [[ ${1:-} != --standalone ]] && command -v flightdeck >/dev/null; then
  mode=flightdeck
fi

python3 "$src/migrate-monitors.py" "install-$mode" "$conf/caelestia"
python3 - "$conf/caelestia/screens.json" "$mode" <<'EOF'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text()) if path.exists() else {}
data["rulesTarget"] = sys.argv[2]
data.setdefault("dashboardTab", True)
path.write_text(json.dumps(data, indent=4) + "\n")
EOF
python3 "$src/patch.py" apply "$target" "$conf/caelestia/shell.json"

if [[ $mode == flightdeck ]]; then
  echo "Installed. Monitor rules are shared with FlightDeck (astra-flightdeck.lua)."
else
  echo "Installed. Monitor rules are in screens-monitors.lua."
fi
echo "Pick where it shows (right bar, dashboard tab or off) with Show in at the bottom of the Screens pane."
