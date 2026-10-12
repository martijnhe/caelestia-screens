pragma ComponentBehavior: Bound

import "./screens"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    required property PopoutState popouts

    width: 440
    implicitWidth: 440
    spacing: Tokens.spacing.small

    Component.onCompleted: Displays.refresh()

    // Header
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.padding.medium
        Layout.rightMargin: Tokens.padding.extraSmall
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "desktop_windows"
            color: Colours.palette.m3primary
            fill: 1
            fontStyle: Tokens.font.icon.large
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: Tr.tr("Screens")
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
            }

            StyledText {
                Layout.fillWidth: true
                text: Displays.dirty ? Tr.tr("Unapplied changes") : Tr.trN("%n screen", "%n screens", Displays.monitors.length)
                color: Displays.dirty ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }

        IconButton {
            type: IconButton.Text
            icon: "center_focus_strong"
            onClicked: Displays.identify()
        }

        IconButton {
            type: IconButton.Text
            icon: "refresh"
            onClicked: Displays.refresh()
        }
    }

    ScLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 170
    }

    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: Tr.tr("Drag screens to arrange them; they snap together")
        color: Colours.palette.m3outline
        font: Tokens.font.label.small
    }

    StyledFlickable {
        id: flick

        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(body.implicitHeight, 430)
        contentHeight: body.implicitHeight
        clip: true
        flickableDirection: Flickable.VerticalFlick

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: flick
        }

        ColumnLayout {
            id: body

            width: flick.width - Tokens.padding.small
            spacing: Tokens.spacing.small

            ScScreenSettings {
                Layout.fillWidth: true
            }

            // Night light
            ScSection {
                text: Tr.tr("Night light")
            }

            ScToggle {
                label: Tr.tr("Night light")
                description: Tr.tr("Warmer colours on all screens (%1 K)").arg(Displays.settings.kelvin)
                isOn: Displays.settings.nightLight
                onToggled: value => Displays.setNightLight(value, Displays.settings.kelvin)
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.rightMargin: Tokens.padding.extraSmall
                visible: Displays.settings.nightLight
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "bedtime"
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledSlider {
                    Layout.fillWidth: true
                    implicitHeight: Tokens.padding.medium * 2
                    from: 1500
                    to: 6500
                    stepSize: 100
                    value: Displays.settings.kelvin
                    interactionOnMove: false
                    onInteraction: v => Displays.setNightLight(true, Math.round(v / 100) * 100)
                }

                StyledText {
                    Layout.preferredWidth: 52
                    horizontalAlignment: Text.AlignRight
                    text: `${Displays.settings.kelvin} K`
                    font: Tokens.font.body.small
                }
            }

            // Profiles
            ScSection {
                text: Tr.tr("Profiles")
            }

            StyledText {
                Layout.fillWidth: true
                visible: Displays.settings.profiles.length === 0
                text: Tr.tr("Save a layout to restore it later, or automatically when its screens are connected.")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                wrapMode: Text.Wrap
            }

            Repeater {
                model: Displays.settings.profiles

                RowLayout {
                    id: profile

                    required property var modelData
                    readonly property bool matches: Displays.profileMatches(modelData)

                    Layout.fillWidth: true
                    Layout.rightMargin: Tokens.padding.extraSmall
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "bookmark"
                        color: profile.matches ? Colours.palette.m3primary : Colours.palette.m3outline
                        fill: profile.matches ? 1 : 0
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: profile.modelData.name
                        elide: Text.ElideRight
                        color: profile.matches ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    }

                    TextButton {
                        type: TextButton.Tonal
                        visible: profile.matches
                        text: Tr.tr("Apply")
                        disabled: Displays.confirming
                        onClicked: Displays.applyProfile(profile.modelData)
                    }

                    IconButton {
                        type: IconButton.Text
                        icon: "delete"
                        onClicked: Displays.deleteProfile(profile.modelData.name)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.rightMargin: Tokens.padding.extraSmall
                spacing: Tokens.spacing.small

                ScToggle {
                    Layout.fillWidth: true
                    label: Tr.tr("Apply on connect")
                    description: Tr.tr("Restore a saved layout when its screens are plugged in")
                    isOn: Displays.settings.autoApply
                    onToggled: value => Displays.settings.autoApply = value
                }

                TextButton {
                    type: TextButton.Tonal
                    text: Tr.tr("Save layout")
                    disabled: Displays.dirty
                    onClicked: Displays.saveProfile()
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: Displays.lastError !== ""
        text: Displays.lastError
        color: Colours.palette.m3error
        font: Tokens.font.body.small
        wrapMode: Text.Wrap
    }

    // Footer
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        spacing: Tokens.spacing.small

        IconTextButton {
            Layout.fillWidth: true
            type: IconTextButton.Tonal
            verticalPadding: Tokens.padding.extraSmall
            disabled: !Displays.dirty || Displays.confirming
            text: Tr.tr("Undo")
            icon: "undo"
            onClicked: Displays.discard()
        }

        IconTextButton {
            Layout.fillWidth: true
            inactiveColour: Colours.palette.m3primaryContainer
            inactiveOnColour: Colours.palette.m3onPrimaryContainer
            verticalPadding: Tokens.padding.extraSmall
            disabled: !Displays.dirty || Displays.confirming
            text: Displays.confirming ? Tr.tr("Keep? %1s").arg(Displays.countdown) : Tr.tr("Apply")
            icon: "check"
            onClicked: Displays.apply()
        }
    }
}
