#!/bin/bash
# Remove the Screens dashboard tab. Settings in screens.json are kept. Monitor rules
# the widget owned move back into hypr-user.lua; rules shared with FlightDeck stay in
# astra-flightdeck.lua, where FlightDeck manages them.
set -euo pipefail

src=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
conf=${XDG_CONFIG_HOME:-$HOME/.config}
target=$conf/quickshell/caelestia

python3 "$src/migrate-monitors.py" uninstall "$conf/caelestia" || true
[[ -d $target ]] && python3 "$src/patch.py" revert "$target"

echo "Removed the Screens tab."
