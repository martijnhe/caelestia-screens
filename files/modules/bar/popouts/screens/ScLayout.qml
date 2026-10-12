pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Screens drawn at their real size and position. Drag a tile and it snaps flush
// to a neighbour when dropped; click a tile to select it.
StyledRect {
    id: root

    readonly property list<var> tiles: Object.values(Displays.draft).filter(r => !r.disabled && !r.mirror)
    readonly property var bounds: {
        let w = 1;
        let h = 1;
        for (const r of tiles) {
            const s = Displays.logicalSize(r);
            w = Math.max(w, r.x + s.w);
            h = Math.max(h, r.y + s.h);
        }
        return {
            w,
            h
        };
    }
    readonly property real pad: Tokens.padding.large
    readonly property real factor: Math.min((width - pad * 2) / bounds.w, (height - pad * 2) / bounds.h)
    readonly property real offsetX: (width - bounds.w * factor) / 2
    readonly property real offsetY: (height - bounds.h * factor) / 2

    radius: Tokens.rounding.medium
    color: Colours.tPalette.m3surfaceContainerHigh
    clip: true

    Repeater {
        model: root.tiles

        StyledRect {
            id: tile

            required property var modelData
            readonly property var size: Displays.logicalSize(modelData)
            readonly property bool isSelected: Displays.selected === modelData.output
            readonly property var mon: Displays.monitors.find(m => m.name === tile.modelData.output)

            readonly property real homeX: root.offsetX + modelData.x * root.factor
            readonly property real homeY: root.offsetY + modelData.y * root.factor

            x: homeX
            y: homeY
            width: Math.max(8, size.w * root.factor - 2)
            height: Math.max(8, size.h * root.factor - 2)
            z: drag.active ? 10 : isSelected ? 5 : 1
            radius: Tokens.rounding.small
            color: isSelected ? Colours.palette.m3primaryContainer : Colours.palette.m3secondaryContainer
            border.width: isSelected ? 2 : 0
            border.color: Colours.palette.m3primary
            opacity: drag.active ? 0.85 : 1

            Behavior on x {
                enabled: !drag.active

                Anim {}
            }
            Behavior on y {
                enabled: !drag.active

                Anim {}
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.small * 2
                spacing: 0

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Displays.label(tile.mon)
                    color: tile.isSelected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: tile.height > 48
                    text: `${tile.modelData.output} · ${tile.modelData.w}×${tile.modelData.h}${tile.modelData.scale !== 1 ? ` · ${(+tile.modelData.scale).toFixed(2)}×` : ""}`
                    color: tile.isSelected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            DragHandler {
                id: drag

                target: tile
                enabled: !Displays.confirming
                onActiveChanged: {
                    if (active) {
                        Displays.selected = tile.modelData.output;
                    } else {
                        Displays.moveTo(tile.modelData.output, (tile.x - root.offsetX) / root.factor, (tile.y - root.offsetY) / root.factor);
                        // Dragging replaced the bindings; follow the snapped position again
                        tile.x = Qt.binding(() => tile.homeX);
                        tile.y = Qt.binding(() => tile.homeY);
                    }
                }
            }

            TapHandler {
                onTapped: Displays.selected = tile.modelData.output
            }
        }
    }
}
