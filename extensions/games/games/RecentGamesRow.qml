pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Sylphrena.Config
import qs.components
import qs.components.images
import qs.services

RowLayout {
    id: root

    // Injected by the games tab (the extension's service)
    required property var service

    property int maxGames: 5 + Math.min(3, root.service.nonSteamGames.length)

    spacing: Tokens.spacing.small

    Repeater {
        model: root.service.pickerGames.slice(0, root.maxGames)

        Item {
            id: card

            required property var modelData
            required property int index

            readonly property bool selected: modelData.appId === root.service.focusAppId
            readonly property bool playing: modelData.appId === (root.service.profile?.gameId ?? "")

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: 84

            scale: selected ? 1 : hover.pressed ? 0.95 : 0.97
            opacity: 0

            Component.onCompleted: opacity = Qt.binding(() => selected || hover.containsMouse ? 1 : 0.8)

            Behavior on scale {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.large
                color: card.selected ? Colours.palette.m3primary : "transparent"
            }

            ClipRect {
                property real inset: card.selected ? 3 : 0

                anchors.fill: parent
                anchors.margins: inset
                radius: Tokens.rounding.large - inset

                Behavior on inset {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }
                color: Colours.palette.m3surfaceContainerHighest

                SteamArt {
                    anchors.fill: parent
                    candidates: root.service.artCandidates(card.modelData.appId, "")
                }
            }

            StyledRect {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Tokens.padding.small
                visible: card.playing
                implicitWidth: 22
                implicitHeight: 22
                radius: Tokens.rounding.full
                color: Colours.palette.m3tertiaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    fill: 1
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onTertiaryContainer
                }
            }

            StateLayer {
                id: hover

                radius: Tokens.rounding.large
                color: "white"
                onClicked: root.service.setFocusApp(card.modelData.appId, card.modelData.name)
            }
        }
    }
}
