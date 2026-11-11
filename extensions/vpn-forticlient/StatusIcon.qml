pragma ComponentBehavior: Bound

import QtQuick
import Sylphrena.Config
import qs.components
import qs.services

Item {
    id: root

    // Injected by the base: the extension and its service (see services/Extensions.qml)
    required property var ext
    required property var service

    required property color colour

    implicitWidth: icon.implicitWidth
    implicitHeight: icon.implicitHeight

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        animate: true
        // Shield-style glyphs (like KDE network-vpn)
        text: root.service.connected ? "verified_user" : "remove_moderator"
        fill: root.service.connected ? 1 : 0
        // Always follow EntryWrapper colour so hover (m3onPrimary on m3primary pill) stays readable
        color: root.colour
        opacity: root.service.busy ? 0.55 : 1

        SequentialAnimation on opacity {
            running: root.service.busy
            loops: Animation.Infinite
            alwaysRunToEnd: true
            Anim {
                from: 1
                to: 0.35
                duration: Tokens.anim.durations.large
            }
            Anim {
                from: 0.35
                to: 1
                duration: Tokens.anim.durations.large
            }
        }
    }
}
