import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import martijnhe.screens

// Bar entry: the screens icon in its own pill, like the status icons group
StyledRect {
    id: root

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: icon.implicitHeight + Tokens.padding.medium * 2

    ScreensStatus {
        id: icon

        anchors.centerIn: parent
        colour: Colours.palette.m3secondary
    }
}
