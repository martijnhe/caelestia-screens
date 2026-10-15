pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Split button whose options unfold inline below it, so the list stays inside
// the popout (the shell's Menu overlays the window and loses hover there).
// Either half toggles the list; picking an option selects it and folds it up.
ColumnLayout {
    id: root

    // [{ value, text }]
    property list<var> options
    property var current
    property string icon
    property string fallbackText
    property bool expanded

    readonly property var currentOption: options.find(o => o.value === current) ?? null

    signal selected(value: var)

    Layout.fillWidth: true
    Layout.rightMargin: Tokens.padding.extraSmall
    spacing: Tokens.spacing.extraSmall

    onCurrentChanged: expanded = false

    RowLayout {
        Layout.fillWidth: true
        spacing: Math.floor(Tokens.spacing.extraSmall / 2)

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: expandBtn.implicitHeight
            radius: implicitHeight / 2 * Math.min(1, Tokens.rounding.scale)
            topRightRadius: Tokens.rounding.medium / 2
            bottomRightRadius: Tokens.rounding.medium / 2
            color: Colours.palette.m3secondaryContainer
            opacity: root.options.length ? 1 : 0.4

            StateLayer {
                topRightRadius: parent.topRightRadius
                bottomRightRadius: parent.bottomRightRadius
                color: Colours.palette.m3onSecondaryContainer
                disabled: !root.options.length
                onClicked: root.expanded = !root.expanded
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.small

                MaterialIcon {
                    visible: root.icon
                    text: root.icon
                    color: Colours.palette.m3onSecondaryContainer
                    fill: 1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.currentOption?.text ?? root.fallbackText
                    color: Colours.palette.m3onSecondaryContainer
                    elide: Text.ElideRight
                }
            }
        }

        StyledRect {
            id: expandBtn

            property real rad: root.expanded ? implicitHeight / 2 * Math.min(1, Tokens.rounding.scale) : Tokens.rounding.medium / 2

            implicitWidth: implicitHeight
            implicitHeight: expandIcon.implicitHeight + Tokens.padding.small * 2
            radius: implicitHeight / 2 * Math.min(1, Tokens.rounding.scale)
            topLeftRadius: rad
            bottomLeftRadius: rad
            color: Colours.palette.m3secondaryContainer
            opacity: root.options.length ? 1 : 0.4

            StateLayer {
                rect.topLeftRadius: parent.topLeftRadius
                rect.bottomLeftRadius: parent.bottomLeftRadius
                color: Colours.palette.m3onSecondaryContainer
                disabled: !root.options.length
                onClicked: root.expanded = !root.expanded
            }

            MaterialIcon {
                id: expandIcon

                anchors.centerIn: parent
                text: "expand_more"
                color: Colours.palette.m3onSecondaryContainer
                rotation: root.expanded ? 180 : 0

                Behavior on rotation {
                    Anim {}
                }
            }

            Behavior on rad {
                Anim {}
            }
        }
    }

    // Inline option list
    StyledRect {
        Layout.fillWidth: true
        Layout.preferredHeight: root.expanded ? list.implicitHeight + Tokens.padding.extraSmall * 2 : 0
        visible: Layout.preferredHeight > 0
        clip: true
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHigh

        Behavior on Layout.preferredHeight {
            Anim {}
        }

        ColumnLayout {
            id: list

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.extraSmall
            spacing: 0

            Repeater {
                model: root.options

                StyledRect {
                    id: option

                    required property var modelData
                    readonly property bool active: modelData.value === root.current

                    Layout.fillWidth: true
                    implicitHeight: optionRow.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.small
                    color: active ? Colours.palette.m3tertiaryContainer : "transparent"

                    StateLayer {
                        color: option.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                        disabled: !root.expanded
                        onClicked: {
                            root.expanded = false;
                            if (!option.active)
                                root.selected(option.modelData.value);
                        }
                    }

                    RowLayout {
                        id: optionRow

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        StyledText {
                            Layout.fillWidth: true
                            text: option.modelData.text
                            color: option.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                        }

                        MaterialIcon {
                            visible: option.active
                            text: "check"
                            color: Colours.palette.m3onTertiaryContainer
                        }
                    }
                }
            }
        }
    }
}
