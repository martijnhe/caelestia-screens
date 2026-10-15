pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Caelestia
import martijnhe.screens.components

// Monitor layout and settings for Hyprland's Lua config.
//
// Changes are drafted, applied live with `hyprctl eval 'hl.monitor(...)'`, and
// only written to ~/.config/caelestia/screens-monitors.lua once kept. Unkept
// changes revert after a countdown.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || `${home}/.config`
    readonly property string rulesPath: `${configHome}/caelestia/screens-monitors.lua`
    readonly property string flightDeckPath: `${configHome}/caelestia/astra-flightdeck.lua`
    readonly property bool sharedRules: settings.rulesTarget === "flightdeck"
    property bool flightDeckInstalled

    property list<var> monitors: [] // live state from hyprctl
    property var caps: ({}) // name -> what the screen supports, from its EDID
    property var draft: ({}) // name -> rule being edited
    property string selected
    property bool dirty
    property string lastError

    // Apply / keep / revert
    property var revertRules: null
    property int countdown: 0
    readonly property bool confirming: revertRules !== null

    property alias settings: settingsAdapter
    property alias profileStore: profilesAdapter
    property bool settingsLoaded
    property bool profilesLoaded

    readonly property list<var> outputs: monitors.map(m => m.name)
    readonly property var selectedMonitor: monitors.find(m => m.name === selected) ?? monitors[0] ?? null
    readonly property var selectedRule: selectedMonitor ? draft[selectedMonitor.name] ?? null : null
    readonly property int enabledCount: Object.values(draft).filter(r => !r.disabled && !r.mirror).length

    // ---------- Helpers ----------

    function desc(m: var): string {
        return `${m.make} ${m.model} ${m.serial}`.trim();
    }

    function label(m: var): string {
        return m ? (m.model || m.name) : "";
    }

    function parseMode(mode: string): var {
        const m = mode.match(/(\d+)x(\d+)@([\d.]+)/);
        return m ? {
            w: +m[1],
            h: +m[2],
            rate: +m[3]
        } : null;
    }

    function ruleFromMonitor(m: var): var {
        return {
            output: m.name,
            w: m.width,
            h: m.height,
            rate: Math.round(m.refreshRate * 100) / 100,
            x: m.x,
            y: m.y,
            scale: m.scale,
            transform: m.transform,
            vrr: m.vrr ? 1 : 0,
            bitdepth: /2101010/.test(m.currentFormat ?? "") ? 10 : 8,
            hdr: (m.colorManagementPreset ?? "").includes("hdr"),
            mirror: m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : "",
            disabled: m.disabled
        };
    }

    // Size on the desktop, after rotation and scale
    function logicalSize(r: var): var {
        const rot = r.transform % 2 === 1;
        return {
            w: Math.round((rot ? r.h : r.w) / r.scale),
            h: Math.round((rot ? r.w : r.h) / r.scale)
        };
    }

    function validScale(w: int, h: int, scale: real): real {
        if (w <= 0 || h <= 0 || scale <= 0)
            return scale;
        const base = Math.round(scale * 120);
        for (let d = 0; d <= 120; d++) {
            for (const tick of [base + d, base - d]) {
                if (tick > 0 && (w * 120) % tick === 0 && (h * 120) % tick === 0)
                    return tick / 120;
            }
        }
        return scale;
    }

    function luaRule(r: var): string {
        if (r.disabled)
            return `hl.monitor({ output = "${r.output}", disabled = true })`;
        const parts = [`output = "${r.output}"`, `mode = "${r.w}x${r.h}@${r.rate.toFixed(2)}"`, `position = "${r.x}x${r.y}"`, `scale = ${(+r.scale).toFixed(6)}`, `transform = ${r.transform}`, `bitdepth = ${r.bitdepth}`, `vrr = ${r.vrr}`];
        if (r.hdr)
            parts.push(`cm = "hdr"`);
        if (r.mirror)
            parts.push(`mirror = "${r.mirror}"`);
        return `hl.monitor({ ${parts.join(", ")} })`;
    }

    // What a screen supports. Unknown (no EDID) means "allow everything".
    function capsFor(name: string): var {
        return caps[name] ?? {
            known: false,
            bpc: 10,
            hdr: true,
            vrr: true
        };
    }

    // `edid-decode` output for each connector, separated by "@@ NAME" lines
    function parseCaps(text: string): void {
        const out = {};
        for (const chunk of text.split(/^@@ /m).slice(1)) {
            const name = chunk.split("\n")[0].trim();
            if (!/Block 0|EDID Structure|Manufacturer/i.test(chunk))
                continue;
            const range = chunk.match(/Monitor ranges[^:]*:\s*(\d+)-(\d+) Hz V/);
            const min = range ? +range[1] : 0;
            const max = range ? +range[2] : 0;
            const continuous = /continuous frequencies/i.test(chunk);
            const freesync = /Vendor-Specific Data Block \(AMD\)/.test(chunk);
            const nits = chunk.match(/Desired content max luminance:[^(]*\(([\d.]+) cd/);
            out[name] = {
                known: true,
                bpc: +(chunk.match(/Bits per primary color channel: (\d+)/)?.[1] ?? 8),
                hdr: /SMPTE ST2084/.test(chunk),
                hlg: /Hybrid Log-Gamma/i.test(chunk),
                maxNits: nits ? Math.round(+nits[1]) : 0,
                wideColour: /BT2020RGB|DCI-P3/.test(chunk),
                // Same test amdgpu uses for vrr_capable, plus AMD's FreeSync block
                vrr: (continuous && max - min > 10) || (freesync && max - min > 10),
                vrrMin: min,
                vrrMax: max
            };
        }
        caps = out;
    }

    function capsText(name: string): string {
        const c = caps[name];
        if (!c?.known)
            return "";
        const parts = [`${c.bpc}-bit`];
        if (c.hdr)
            parts.push(c.maxNits ? qsTr("HDR10 up to %1 nits").arg(c.maxNits) : qsTr("HDR10"));
        if (c.wideColour)
            parts.push("BT.2020");
        parts.push(c.vrr ? qsTr("VRR %1–%2 Hz").arg(c.vrrMin).arg(c.vrrMax) : qsTr("no VRR"));
        return parts.join(" · ");
    }

    function fail(message: string): void {
        lastError = message;
        if (settings.notifications)
            Toaster.toast(qsTr("Screens"), message, "desktop_access_disabled", Toast.Error);
    }

    // ---------- State ----------

    function refresh(): void {
        monitorsProc.running = true;
    }

    function resetDraft(): void {
        const d = {};
        for (const m of monitors)
            d[m.name] = ruleFromMonitor(m);
        draft = d;
        dirty = false;
        if (!monitors.some(m => m.name === selected))
            selected = (monitors.find(m => m.focused) ?? monitors[0])?.name ?? "";
    }

    function update(name: string, changes: var): void {
        const d = Object.assign({}, draft);
        d[name] = Object.assign({}, d[name], changes);
        if ("w" in changes || "h" in changes || "scale" in changes)
            d[name].scale = validScale(d[name].w, d[name].h, d[name].scale);
        // Changing size or rotation can create overlaps; re-pack around the change
        if ("w" in changes || "h" in changes || "scale" in changes || "transform" in changes)
            d[name] = Object.assign(d[name], snap(d, name, d[name].x, d[name].y, true));
        draft = normalize(d);
        dirty = true;
    }

    // ---------- Layout snapping ----------

    function rects(d: var, except: string): list<var> {
        return Object.values(d).filter(r => r.output !== except && !r.disabled && !r.mirror).map(r => {
            const s = logicalSize(r);
            return {
                x: r.x,
                y: r.y,
                w: s.w,
                h: s.h
            };
        });
    }

    function overlaps(a: var, b: var): bool {
        return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
    }

    function touches(a: var, b: var): bool {
        const xTouch = (a.x === b.x + b.w || a.x + a.w === b.x) && a.y < b.y + b.h && a.y + a.h > b.y;
        const yTouch = (a.y === b.y + b.h || a.y + a.h === b.y) && a.x < b.x + b.w && a.x + a.w > b.x;
        return xTouch || yTouch;
    }

    // Flush against a neighbour, no overlap. Centre-snap when stacked vertically.
    function snap(d: var, name: string, x: real, y: real, force: bool): var {
        const r = d[name];
        const size = logicalSize(r);
        const others = rects(d, name);
        if (others.length === 0)
            return {
                x: 0,
                y: 0
            };

        const candidates = [];
        for (const o of others) {
            const ys = [y, o.y, o.y + o.h - size.h, o.y + (o.h - size.h) / 2];
            const xs = [x, o.x, o.x + o.w - size.w, o.x + (o.w - size.w) / 2];
            for (const cy of ys) {
                candidates.push({ x: o.x - size.w, y: cy }); // left of o
                candidates.push({ x: o.x + o.w, y: cy }); // right of o
            }
            for (const cx of xs) {
                candidates.push({ x: cx, y: o.y - size.h }); // above o
                candidates.push({ x: cx, y: o.y + o.h }); // below o
            }
        }

        let best = null;
        let bestDist = Infinity;
        for (const c of candidates) {
            const rect = {
                x: Math.round(c.x),
                y: Math.round(c.y),
                w: size.w,
                h: size.h
            };
            if (others.some(o => overlaps(rect, o)) || !others.some(o => touches(rect, o)))
                continue;
            // Prefer the spot nearest the drop point; nudge towards centred stacks
            let dist = Math.hypot(rect.x - x, rect.y - y);
            if (others.some(o => (rect.y === o.y + o.h || rect.y + rect.h === o.y) && Math.abs(rect.x + rect.w / 2 - (o.x + o.w / 2)) < 1))
                dist -= 120;
            if (dist < bestDist) {
                bestDist = dist;
                best = rect;
            }
        }
        return best ? {
            x: best.x,
            y: best.y
        } : {
            x: Math.round(x),
            y: Math.round(y)
        };
    }

    // Shift everything so the layout starts at 0,0
    function normalize(d: var): var {
        const active = Object.values(d).filter(r => !r.disabled && !r.mirror);
        if (active.length === 0)
            return d;
        const minX = Math.min(...active.map(r => r.x));
        const minY = Math.min(...active.map(r => r.y));
        const out = {};
        for (const k of Object.keys(d))
            out[k] = d[k].disabled || d[k].mirror ? d[k] : Object.assign({}, d[k], {
                x: d[k].x - minX,
                y: d[k].y - minY
            });
        return out;
    }

    function moveTo(name: string, x: real, y: real): void {
        const d = Object.assign({}, draft);
        d[name] = Object.assign({}, d[name], snap(d, name, x, y, false));
        draft = normalize(d);
        dirty = true;
    }

    // ---------- Apply / keep / revert ----------

    function apply(): void {
        if (!dirty)
            return;
        if (enabledCount === 0)
            return fail(qsTr("At least one screen must stay on"));
        revertRules = monitors.map(m => luaRule(ruleFromMonitor(m)));
        evalLua(Object.values(draft).map(luaRule), () => {
            countdown = settings.revertSeconds;
            countdownTimer.restart();
            delayedRefresh.restart();
        });
    }

    function keep(): void {
        countdownTimer.stop();
        revertRules = null;
        dirty = false;
        writeRules(Object.values(draft));
        if (settings.notifications)
            Toaster.toast(qsTr("Screens"), qsTr("Display settings saved"), "desktop_windows", Toast.Success);
    }

    function revert(): void {
        countdownTimer.stop();
        const rules = revertRules;
        revertRules = null;
        if (rules)
            evalLua(rules, () => {
                delayedRefresh.restart();
                resetTimer.restart();
            });
    }

    function discard(): void {
        resetDraft();
    }

    function evalLua(rules: var, onDone: var): void {
        const proc = luaComp.createObject(root, {
            command: ["hyprctl", "eval", rules.join("\n")],
            onDone: onDone ?? null
        });
        proc.running = true;
    }

    function flightDeckRule(r: var): string {
        const lines = [`    output = "${r.output}",`, `    disabled = ${r.disabled ? "true" : "false"},`];
        if (!r.disabled) {
            lines.push(`    mode = "${r.w}x${r.h}@${r.rate.toFixed(2)}",`);
            lines.push(`    position = "${r.x}x${r.y}",`);
            lines.push(`    scale = ${(+r.scale).toFixed(6)},`);
            if (r.transform > 0)
                lines.push(`    transform = ${r.transform},`);
            lines.push(`    bitdepth = ${r.bitdepth},`);
            lines.push(`    vrr = ${r.vrr},`);
            if (r.hdr)
                lines.push(`    cm = "hdr",`);
            if (r.mirror)
                lines.push(`    mirror = "${r.mirror}",`);
        }
        return ["hl.monitor({", ...lines, "})"].join("\n");
    }

    function writeFlightDeckRules(rules: var): void {
        flightDeckFile.reload();
        const text = flightDeckFile.text() || "-- Generated by FlightDeck\n";
        const section = /-- Monitors\n(?:hl\.monitor\(\{[\s\S]*?\}\)\n)*\n?/;
        const old = text.match(section)?.[0] ?? "";
        const current = rules.map(r => r.output);
        const preserved = (old.match(/hl\.monitor\(\{[\s\S]*?\}\)/g) ?? []).filter(block => {
            const out = block.match(/output\s*=\s*"([^"]*)"/)?.[1];
            return out !== undefined && !current.includes(out);
        });
        const block = ["-- Monitors", ...rules.map(flightDeckRule), ...preserved, "", ""].join("\n");
        const next = old ? text.replace(old, block) : `${text.replace(/\n*$/, "\n\n")}${block}`;
        flightDeckFile.setText(next);
    }

    function openFlightDeck(): void {
        Quickshell.execDetached(["flightdeck"]);
    }

    // Writes the monitors file; keeps rules for outputs that aren't connected now
    function writeRules(rules: var): void {
        if (sharedRules)
            return writeFlightDeckRules(rules);
        const current = rules.map(r => r.output);
        const kept = (rulesFile.text() || "").match(/hl\.monitor\(\{[\s\S]*?\}\)/g) ?? [];
        const preserved = kept.filter(block => {
            const out = block.match(/output\s*=\s*"([^"]*)"/)?.[1];
            return out !== undefined && !current.includes(out);
        });
        const text = ["-- Written by the Caelestia Screens widget. Edit with the widget, or by hand when it's closed.", "", ...rules.map(luaRule), ...(preserved.length ? ["", "-- Screens that aren't connected right now", ...preserved] : []), ""].join("\n");
        rulesFile.setText(text);
    }

    // ---------- Profiles ----------

    function sharedRule(r: var): var {
        return {
            output: r.output,
            disabled: !!r.disabled,
            mode: `${r.w}x${r.h}@${(+r.rate).toFixed(2)}`,
            position: `${r.x}x${r.y}`,
            scale: +r.scale,
            transform: r.transform ?? 0,
            vrr: r.vrr ?? 0,
            bitdepth: r.bitdepth ?? 8,
            mirror: r.mirror || "",
            cm: r.hdr ? "hdr" : "srgb"
        };
    }

    function draftRule(s: var, m: var): var {
        const base = draft[m.name] ?? ruleFromMonitor(m);
        const mode = parseMode(s.mode ?? "");
        const pos = (s.position ?? "").match(/(-?\d+)x(-?\d+)/);
        return {
            output: m.name,
            w: mode?.w ?? base.w,
            h: mode?.h ?? base.h,
            rate: mode ? Math.round(mode.rate * 100) / 100 : base.rate,
            x: pos ? +pos[1] : base.x,
            y: pos ? +pos[2] : base.y,
            scale: s.scale ?? base.scale,
            transform: s.transform ?? base.transform,
            vrr: s.vrr === true ? 1 : s.vrr === false ? 0 : (s.vrr ?? base.vrr),
            bitdepth: s.bitdepth ?? base.bitdepth,
            hdr: (s.cm ?? "").includes("hdr"),
            mirror: s.mirror && s.mirror !== "none" ? s.mirror : "",
            disabled: !!s.disabled
        };
    }

    function migrateProfiles(): void {
        if (!settingsLoaded || !profilesLoaded || settings.profiles.length === 0)
            return;
        const taken = profileStore.profiles.map(p => p.name);
        const added = settings.profiles.filter(p => !taken.includes(p.name)).map(p => {
            const outputs = {};
            for (const key of Object.keys(p.outputs))
                outputs[key] = p.outputs[key].mode ? p.outputs[key] : sharedRule(p.outputs[key]);
            return {
                name: p.name,
                outputs
            };
        });
        if (added.length)
            profileStore.profiles = [...profileStore.profiles, ...added];
        settings.profiles = [];
    }

    function saveProfile(): void {
        const outputs = {};
        for (const m of monitors)
            outputs[desc(m)] = sharedRule(draft[m.name]);
        const names = monitors.filter(m => !draft[m.name]?.disabled).map(label);
        let name = names.join(" + ") || qsTr("Layout");
        const taken = profileStore.profiles.map(p => p.name);
        let n = 2;
        const base = name;
        while (taken.includes(name))
            name = `${base} (${n++})`;
        profileStore.profiles = [...profileStore.profiles, {
                name,
                outputs
            }];
        if (settings.notifications)
            Toaster.toast(qsTr("Profile saved"), name, "bookmark_add", Toast.Success);
    }

    function deleteProfile(name: string): void {
        profileStore.profiles = profileStore.profiles.filter(p => p.name !== name);
    }

    function profileMatches(p: var): bool {
        const keys = Object.keys(p.outputs);
        return keys.length === monitors.length && monitors.every(m => keys.includes(desc(m)));
    }

    // Loads a profile into the draft (outputs matched by make/model/serial)
    function loadProfile(p: var): void {
        const d = Object.assign({}, draft);
        for (const m of monitors) {
            const r = p.outputs[desc(m)];
            if (r)
                d[m.name] = draftRule(r, m);
        }
        draft = normalize(d);
        dirty = true;
    }

    function applyProfile(p: var): void {
        loadProfile(p);
        apply();
    }

    // ---------- Night light ----------

    function setNightLight(on: bool, kelvin: int): void {
        settings.nightLight = on;
        settings.kelvin = kelvin;
        sunsetProc.running = false;
        if (on)
            sunsetRestart.restart();
    }

    // ---------- Find ----------

    property bool identifying
    function identify(): void {
        identifying = true;
        identifyTimer.restart();
    }

    // ---------- Processes ----------

    Process {
        id: monitorsProc

        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text).filter(m => !m.name.startsWith("FALLBACK") && !m.name.startsWith("HEADLESS"));
                } catch (e) {
                    return;
                }
                if (!root.dirty && !root.confirming)
                    root.resetDraft();
                const names = root.monitors.map(m => m.name).sort().join(" ");
                if (names !== edidProc.names) {
                    edidProc.names = names;
                    edidProc.command = ["sh", "-c", "for n in \"$@\"; do for f in /sys/class/drm/card*-\"$n\"/edid; do [ \"$(wc -c < \"$f\" 2>/dev/null || echo 0)\" -gt 0 ] || continue; echo \"@@ $n\"; edid-decode \"$f\" 2>/dev/null; break; done; done", "sh", ...root.monitors.map(m => m.name)];
                    edidProc.running = true;
                }
            }
        }
    }

    // Reads each screen's EDID (on start and whenever the set of screens changes)
    Process {
        id: edidProc

        property string names

        stdout: StdioCollector {
            onStreamFinished: root.parseCaps(text)
        }
    }

    Component {
        id: luaComp

        Process {
            id: proc

            property var onDone

            stderr: StdioCollector {
                id: err
            }
            stdout: StdioCollector {
                id: out
            }
            onExited: code => {
                Qt.callLater(() => {
                    const msg = (out.text + err.text).trim();
                    if (code !== 0 || (msg && msg !== "ok" && !/^ok/.test(msg)))
                        root.fail(msg || qsTr("Hyprland rejected the change"));
                    proc.onDone?.();
                    proc.destroy();
                });
            }
        }
    }

    Process {
        id: sunsetProc

        command: ["hyprsunset", "-t", `${root.settings.kelvin}`]
    }

    Timer {
        id: sunsetRestart

        interval: 300
        onTriggered: {
            if (root.settings.nightLight)
                sunsetProc.running = true;
        }
    }

    Timer {
        id: countdownTimer

        interval: 1000
        repeat: true
        onTriggered: {
            if (--root.countdown <= 0)
                root.revert();
        }
    }

    Timer {
        id: delayedRefresh

        interval: 800
        onTriggered: root.refresh()
    }

    Timer {
        id: resetTimer

        interval: 1200
        onTriggered: root.resetDraft()
    }

    Timer {
        id: identifyTimer

        interval: 3500
        onTriggered: root.identifying = false
    }

    // Monitor hotplug: refresh, then apply a matching profile when enabled
    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "monitoradded" || event.name === "monitorremoved") {
                hotplugTimer.restart();
            }
        }

        target: Hyprland
    }

    Timer {
        id: hotplugTimer

        interval: 1500
        onTriggered: {
            root.refresh();
            if (root.profileStore.autoApply && !root.confirming)
                autoApplyTimer.restart();
        }
    }

    Timer {
        id: autoApplyTimer

        interval: 800
        onTriggered: {
            const p = root.profileStore.profiles.find(p => root.profileMatches(p));
            if (!p)
                return;
            root.loadProfile(p);
            root.evalLua(Object.values(root.draft).map(root.luaRule), () => {
                root.dirty = false;
                root.writeRules(Object.values(root.draft));
                root.refresh();
                if (root.settings.notifications)
                    Toaster.toast(qsTr("Screens"), qsTr("Applied profile “%1”").arg(p.name), "desktop_windows", Toast.Info);
            });
        }
    }

    FileView {
        id: flightDeckFile

        path: root.flightDeckPath
        printErrors: false
        blockLoading: true
    }

    Process {
        command: ["sh", "-c", "command -v flightdeck"]
        running: true
        onExited: code => root.flightDeckInstalled = code === 0
    }

    FileView {
        id: rulesFile

        path: root.rulesPath
        printErrors: false
        blockLoading: true
    }

    FileView {
        path: `${root.configHome}/caelestia/screens.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }
        onLoaded: {
            root.settingsLoaded = true;
            root.migrateProfiles();
            if (root.settings.nightLight)
                sunsetRestart.restart();
        }

        JsonAdapter {
            id: settingsAdapter

            property list<var> profiles: []
            property bool autoApply: true
            property bool nightLight: false
            property int kelvin: 4000
            property int revertSeconds: 20
            property bool notifications: true
            property bool dashboardTab: true
            property string rulesTarget: "screens"
        }
    }

    FileView {
        path: `${root.configHome}/caelestia/display-profiles.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
            root.profilesLoaded = true;
            root.migrateProfiles();
        }
        onLoaded: {
            root.profilesLoaded = true;
            root.migrateProfiles();
        }

        JsonAdapter {
            id: profilesAdapter

            property list<var> profiles: []
            property bool autoApply: true
        }
    }

    // Find and Keep/Revert overlays live with the service, not the popout
    property var overlays: null

    Component.onCompleted: {
        refresh();
        const comp = Qt.createComponent(Qt.resolvedUrl("components/ScOverlays.qml"));
        if (comp.status === Component.Ready)
            overlays = comp.createObject(root);
        else
            console.warn("Screens overlays:", comp.errorString());
    }
}
