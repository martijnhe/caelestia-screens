import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Small selectable pill with optional icon, used for tabs and choices
StyledRect {
    id: root

    property string text
    property string icon
    property bool checked
    property bool busy
    property bool disabled

    signal clicked

    implicitWidth: row.implicitWidth + Tokens.padding.medium * 2
    implicitHeight: row.implicitHeight + Tokens.padding.extraSmall * 2
    radius: Tokens.rounding.full
    color: checked ? Colours.palette.m3secondaryContainer : "transparent"
    border.width: checked ? 0 : 1
    border.color: Colours.palette.m3outlineVariant
    opacity: disabled ? 0.4 : 1

    StateLayer {
        color: root.checked ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
        disabled: root.disabled
        onClicked: root.clicked()
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            visible: root.icon
            anchors.verticalCenter: parent.verticalCenter
            text: root.busy ? "progress_activity" : root.icon
            color: label.color
            fill: root.checked ? 1 : 0

            RotationAnimation on rotation {
                running: root.busy
                from: 0
                to: 360
                duration: 1000
                loops: Animation.Infinite
            }
        }

        StyledText {
            id: label

            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.checked ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }
    }
}
