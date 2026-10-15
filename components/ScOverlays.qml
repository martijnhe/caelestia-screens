pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import martijnhe.screens

// Full-screen overlays owned by the Displays service, so they survive the bar
// popout closing while screens are rearranged:
// - Find: each screen's name, large, on that screen
// - Keep / Revert: a confirmation card with a countdown on every screen
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData
            readonly property var mon: Displays.monitors.find(m => m.name === modelData.name) ?? null

            screen: modelData
            visible: Displays.identifying || Displays.confirming
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "caelestia-screens"
            WlrLayershell.keyboardFocus: Displays.confirming ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            anchors {
                left: true
                right: true
                top: true
                bottom: true
            }

            // Only the card takes input; the rest of the screen stays clickable
            mask: Region {
                item: Displays.confirming ? card : null
            }

            contentItem.Config.screen: modelData.name
            contentItem.Tokens.screen: modelData.name

            // Find: big screen name
            StyledRect {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: Displays.confirming ? -card.height : 0
                visible: Displays.identifying
                implicitWidth: idColumn.implicitWidth + Tokens.padding.large * 4
                implicitHeight: idColumn.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.palette.m3primaryContainer

                ColumnLayout {
                    id: idColumn

                    anchors.centerIn: parent
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Displays.label(win.mon) || win.modelData.name
                        color: Colours.palette.m3onPrimaryContainer
                        font.pointSize: Tokens.font.title.small.pointSize * 2.4
                        font.weight: Font.Bold
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: win.mon ? `${win.modelData.name} · ${win.mon.width}×${win.mon.height} @ ${Math.round(win.mon.refreshRate)} Hz` : win.modelData.name
                        color: Colours.palette.m3onPrimaryContainer
                        font: Tokens.font.body.medium
                    }
                }
            }

            // Keep / Revert
            StyledRect {
                id: card

                anchors.centerIn: parent
                visible: Displays.confirming
                implicitWidth: 420
                implicitHeight: cardColumn.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.palette.m3surfaceContainerHigh
                focus: Displays.confirming

                Keys.onReturnPressed: Displays.keep()
                Keys.onEscapePressed: Displays.revert()

                ColumnLayout {
                    id: cardColumn

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: "desktop_windows"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.large
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Keep these display settings?")
                            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: (Displays.countdown === 1 ? qsTr("Reverting in %n second.", "", Displays.countdown) : qsTr("Reverting in %n seconds.", "", Displays.countdown))
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.Wrap
                    }

                    StyledProgressBar {
                        Layout.fillWidth: true
                        value: Displays.countdown / Displays.settings.revertSeconds
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: Tokens.spacing.small

                        TextButton {
                            type: TextButton.Text
                            text: qsTr("Revert")
                            onClicked: Displays.revert()
                        }

                        TextButton {
                            text: qsTr("Keep")
                            onClicked: Displays.keep()
                        }
                    }
                }
            }
        }
    }
}
