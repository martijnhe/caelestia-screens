pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import martijnhe.screens
import martijnhe.screens.components

// Settings for the selected screen. Everything except brightness is drafted and
// takes effect with Apply.
ColumnLayout {
    id: root

    readonly property var mon: Displays.selectedMonitor
    readonly property var rule: Displays.selectedRule
    readonly property list<var> modes: (mon?.availableModes ?? []).map(Displays.parseMode).filter(m => m)
    readonly property list<string> resolutions: [...new Set(modes.map(m => `${m.w}x${m.h}`))]
    readonly property list<real> rates: [...new Set(modes.filter(m => rule && m.w === rule.w && m.h === rule.h).map(m => Math.round(m.rate * 100) / 100))].sort((a, b) => b - a)
    readonly property var screen: Quickshell.screens.find(s => s.name === mon?.name) ?? null
    readonly property var brightnessMonitor: screen ? Brightness.getMonitorForScreen(screen) : null
    readonly property var caps: Displays.capsFor(mon?.name ?? "")
    readonly property list<real> scales: rule ? Displays.supportedScales(rule.w, rule.h) : [1]
    readonly property int scaleIndex: {
        const s = rule?.scale ?? 1;
        let best = 0;
        for (let i = 1; i < scales.length; i++)
            if (Math.abs(scales[i] - s) < Math.abs(scales[best] - s))
                best = i;
        return best;
    }

    function set(changes: var): void {
        Displays.update(rule.output, changes);
    }

    spacing: Tokens.spacing.small
    visible: rule !== null

    // Screen picker
    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: Displays.monitors

            ScChip {
                required property var modelData

                readonly property var r: Displays.draft[modelData.name]

                text: `${Displays.label(modelData)} (${modelData.name})`
                icon: r?.disabled ? "desktop_access_disabled" : r?.mirror ? "screen_share" : "desktop_windows"
                checked: Displays.selected === modelData.name
                onClicked: Displays.selected = modelData.name
            }
        }
    }

    ScToggle {
        label: qsTr("Enabled")
        description: root.rule?.disabled ? qsTr("This screen is off") : `${root.mon?.make ?? ""} ${root.mon?.model ?? ""}`
        isOn: !(root.rule?.disabled ?? false)
        onToggled: value => {
            if (!value && Displays.enabledCount <= 1 && !root.rule.disabled)
                Displays.fail(qsTr("At least one screen must stay on"));
            else
                root.set({
                    disabled: !value
                });
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.rightMargin: Tokens.padding.extraSmall
        visible: text !== ""
        text: Displays.capsText(root.mon?.name ?? "")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
        wrapMode: Text.Wrap
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: !(root.rule?.disabled ?? true)
        spacing: Tokens.spacing.small

        // Brightness is live (DDC/CI or backlight), not part of Apply
        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: Tokens.padding.extraSmall
            visible: root.brightnessMonitor !== null
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "brightness_6"
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledSlider {
                id: brightnessSlider

                Layout.fillWidth: true
                implicitHeight: Tokens.padding.medium * 3
                value: root.brightnessMonitor?.brightness ?? 0
                onInteraction: v => root.brightnessMonitor?.setBrightness(v)
            }

            StyledText {
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: `${Math.round((root.brightnessMonitor?.brightness ?? 0) * 100)}%`
                font: Tokens.font.body.small
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.brightnessMonitor !== null
            text: root.brightnessMonitor?.isDdc ? qsTr("Hardware brightness over DDC/CI") : root.brightnessMonitor?.isAppleDisplay ? qsTr("Apple display brightness") : qsTr("Backlight brightness")
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
        }

        // The shell reads brightness once; re-read it so changes from FlightDeck or the
        // monitor's own buttons show up
        Timer {
            interval: 5000
            repeat: true
            triggeredOnStart: true
            running: root.visible && root.brightnessMonitor !== null
            onTriggered: {
                const m = root.brightnessMonitor;
                if (m && !m.timer.running && !brightnessSlider.dragging)
                    m.initBrightness();
            }
        }

        ScSection {
            text: qsTr("Resolution")
        }

        ScSplitSelect {
            icon: "aspect_ratio"
            fallbackText: qsTr("No modes")
            options: root.resolutions.map(r => ({
                        value: r,
                        text: r.replace("x", "×")
                    }))
            current: root.rule ? `${root.rule.w}x${root.rule.h}` : null
            onSelected: value => {
                const [w, h] = value.split("x").map(Number);
                const best = root.modes.filter(m => m.w === w && m.h === h).sort((a, b) => b.rate - a.rate)[0];
                root.set({
                    w,
                    h,
                    rate: Math.round(best.rate * 100) / 100
                });
            }
        }

        ScSection {
            text: qsTr("Refresh rate")
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: root.rates

                ScChip {
                    required property real modelData

                    text: `${Number.isInteger(modelData) ? modelData : modelData.toFixed(2)} Hz`
                    checked: root.rule && Math.abs(root.rule.rate - modelData) < 0.02
                    onClicked: root.set({
                        rate: modelData
                    })
                }
            }
        }

        ScSection {
            text: qsTr("Scale · %1×").arg((+(root.rule?.scale ?? 1)).toFixed(2))
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: Tokens.padding.extraSmall
            spacing: Tokens.spacing.small

            Repeater {
                model: [1, 1.25, 1.5, 1.75, 2].filter(s => root.scales.some(v => Math.abs(v - s) < 0.001))

                ScChip {
                    required property real modelData

                    text: `${modelData}×`
                    checked: Math.abs((root.rule?.scale ?? 1) - modelData) < 0.005
                    onClicked: root.set({
                        scale: modelData
                    })
                }
            }
        }

        // Steps through the scales this mode supports, starting at 1×
        StyledSlider {
            Layout.fillWidth: true
            Layout.rightMargin: Tokens.padding.extraSmall
            implicitHeight: Tokens.padding.medium * 2
            enabled: root.scales.length > 1
            from: 0
            to: Math.max(1, root.scales.length - 1)
            stepSize: 1
            value: root.scaleIndex
            interactionOnMove: false
            // v is the 0–1 position along the track
            onInteraction: v => root.set({
                scale: root.scales[Math.max(0, Math.min(root.scales.length - 1, Math.round(v * (root.scales.length - 1))))]
            })
        }

        // A tick and label under every scale the slider can stop at
        Item {
            id: ticks

            // Where the slider's handle centre sits at each step
            readonly property real inset: Tokens.spacing.extraSmall + 2
            readonly property real track: width - Tokens.spacing.extraSmall - 4

            Layout.fillWidth: true
            Layout.rightMargin: Tokens.padding.extraSmall
            visible: root.scales.length > 1
            implicitHeight: 6 + Tokens.spacing.extraSmall + tickLabelMetrics.height

            TextMetrics {
                id: tickLabelMetrics

                font: Tokens.font.body.small
                text: "2.67"
            }

            Repeater {
                model: root.scales

                Item {
                    id: tick

                    required property real modelData
                    required property int index
                    readonly property bool current: index === root.scaleIndex
                    // Label every step when they fit, otherwise every other one counted from the last
                    readonly property bool labelled: ticks.track / Math.max(1, root.scales.length - 1) > tickLabelMetrics.width + Tokens.spacing.small || (root.scales.length - 1 - index) % 2 === 0

                    x: ticks.inset + ticks.track * index / Math.max(1, root.scales.length - 1)
                    height: ticks.height

                    StyledRect {
                        x: -width / 2
                        implicitWidth: 2
                        implicitHeight: 6
                        radius: 1
                        color: tick.current ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                    }

                    StyledText {
                        visible: tick.labelled
                        // Keep the first and last labels inside the row
                        x: Math.max(-tick.x, Math.min(ticks.width - tick.x - width, -width / 2))
                        y: 6 + Tokens.spacing.extraSmall
                        text: `${+tick.modelData.toFixed(2)}×`
                        color: tick.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                }
            }
        }

        ScSection {
            text: qsTr("Rotation")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: [
                    {
                        t: 0,
                        label: qsTr("Normal")
                    },
                    {
                        t: 1,
                        label: "90°"
                    },
                    {
                        t: 2,
                        label: "180°"
                    },
                    {
                        t: 3,
                        label: "270°"
                    }
                ]

                ScChip {
                    required property var modelData

                    text: modelData.label
                    icon: modelData.t % 2 ? "stay_current_portrait" : "stay_current_landscape"
                    checked: (root.rule?.transform ?? 0) === modelData.t
                    onClicked: root.set({
                        transform: modelData.t
                    })
                }
            }
        }

        ScSection {
            visible: Displays.monitors.length > 1
            text: qsTr("Mirror")
        }

        Flow {
            Layout.fillWidth: true
            visible: Displays.monitors.length > 1
            spacing: Tokens.spacing.extraSmall

            ScChip {
                text: qsTr("Off")
                checked: !(root.rule?.mirror)
                onClicked: root.set({
                    mirror: ""
                })
            }

            Repeater {
                model: Displays.monitors.filter(m => m.name !== root.rule?.output && !Displays.draft[m.name]?.disabled)

                ScChip {
                    required property var modelData

                    text: qsTr("Mirror %1").arg(Displays.label(modelData))
                    checked: root.rule?.mirror === modelData.name
                    onClicked: root.set({
                        mirror: modelData.name
                    })
                }
            }
        }

        ScSection {
            text: root.caps.vrr && root.caps.known ? qsTr("Variable refresh (VRR) · %1–%2 Hz").arg(root.caps.vrrMin).arg(root.caps.vrrMax) : qsTr("Variable refresh (VRR)")
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.caps.vrr
            text: root.caps.vrrMax ? qsTr("Not supported: this screen runs at a fixed %1–%2 Hz.").arg(root.caps.vrrMin).arg(root.caps.vrrMax) : qsTr("Not supported by this screen.")
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
            wrapMode: Text.Wrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: [
                    {
                        v: 0,
                        label: qsTr("Off")
                    },
                    {
                        v: 1,
                        label: qsTr("Always")
                    },
                    {
                        v: 2,
                        label: qsTr("Fullscreen")
                    },
                    {
                        v: 3,
                        label: qsTr("Games & video")
                    }
                ]

                ScChip {
                    required property var modelData

                    text: modelData.label
                    checked: (root.rule?.vrr ?? 0) === modelData.v
                    disabled: modelData.v !== 0 && !root.caps.vrr
                    onClicked: root.set({
                        vrr: modelData.v
                    })
                }
            }
        }

        ScSection {
            text: qsTr("Colour")
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.caps.known && (!root.caps.hdr || root.caps.bpc < 10)
            text: !root.caps.hdr && root.caps.bpc < 10 ? qsTr("This screen is %1-bit without HDR.").arg(root.caps.bpc) : !root.caps.hdr ? qsTr("This screen doesn't support HDR.") : qsTr("HDR needs a 10-bit screen.")
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
            wrapMode: Text.Wrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            ScChip {
                text: qsTr("8-bit")
                checked: (root.rule?.bitdepth ?? 8) === 8 && !(root.rule?.hdr)
                onClicked: root.set({
                    bitdepth: 8,
                    hdr: false
                })
            }

            ScChip {
                text: qsTr("10-bit")
                checked: (root.rule?.bitdepth ?? 8) === 10 && !(root.rule?.hdr)
                disabled: root.caps.bpc < 10
                onClicked: root.set({
                    bitdepth: 10,
                    hdr: false
                })
            }

            ScChip {
                text: qsTr("HDR")
                icon: "hdr_on"
                checked: root.rule?.hdr ?? false
                disabled: !root.caps.hdr || root.caps.bpc < 10
                onClicked: root.set({
                    bitdepth: 10,
                    hdr: true
                })
            }
        }
    }
}
