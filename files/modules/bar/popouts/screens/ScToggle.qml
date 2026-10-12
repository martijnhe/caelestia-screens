import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Label, description and a switch bound to device state. Shows the new
// value while the write is pending, then follows the confirmed state.
RowLayout {
    id: root

    required property string label
    property string description
    property bool isOn
    property bool busy
    property var optimistic: undefined

    onBusyChanged: {
        if (!busy)
            optimistic = undefined;
    }

    signal toggled(value: bool)

    Layout.fillWidth: true
    Layout.rightMargin: Tokens.padding.extraSmall
    spacing: Tokens.spacing.medium

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        StyledText {
            text: root.label
        }

        StyledText {
            Layout.fillWidth: true
            visible: text
            text: root.description
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.Wrap
        }
    }

    StyledSwitch {
        id: sw

        checked: root.optimistic ?? root.isOn
        disabled: root.busy
        onToggled: {
            root.optimistic = checked;
            root.toggled(checked);
            checked = Qt.binding(() => root.optimistic ?? root.isOn);
        }
    }
}
