import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import martijnhe.screens

// Two-screen mark: a wide screen and a smaller one beside it, drawn in the bar
// colour. Pulses while unconfirmed display changes are waiting for Keep.
Item {
    id: root

    required property color colour

    implicitWidth: sizer.implicitHeight
    implicitHeight: sizer.implicitHeight

    MaterialIcon {
        id: sizer

        visible: false
        text: "desktop_windows"
    }

    Rectangle {
        x: parent.width * 0.04
        y: parent.height * 0.24
        width: parent.width * 0.56
        height: parent.height * 0.42
        radius: 2
        color: "transparent"
        border.width: 2
        border.color: root.colour
    }

    Rectangle {
        x: parent.width * 0.66
        y: parent.height * 0.16
        width: parent.width * 0.3
        height: parent.height * 0.58
        radius: 2
        color: Displays.dirty || Displays.confirming ? root.colour : "transparent"
        border.width: 2
        border.color: root.colour
    }

    Rectangle {
        x: parent.width * 0.2
        y: parent.height * 0.74
        width: parent.width * 0.24
        height: 2
        radius: 1
        color: root.colour
    }

    SequentialAnimation on opacity {
        running: Displays.confirming
        loops: Animation.Infinite
        onStopped: root.opacity = 1

        NumberAnimation {
            to: 0.35
            duration: 500
        }
        NumberAnimation {
            to: 1
            duration: 500
        }
    }
}
