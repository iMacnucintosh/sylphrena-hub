pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Sylphrena.Config
import Sylphrena.I18n
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    // Injected by the base: the extension and its service (see services/Extensions.qml)
    required property var ext
    required property var service

    required property var popouts

    width: Math.max(320, Tokens.sizes.bar.networkWidth)
    spacing: Tokens.spacing.small

    function startConnect(): void {
        root.service.connect(null);
        // Connections that ask for a one-time code continue in the OTP dialog
        if (root.service.otpOpen)
            root.popouts.currentName = "vpnOtp";
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.padding.medium
        Layout.rightMargin: Tokens.padding.extraSmall
        spacing: Tokens.spacing.small

        StyledText {
            Layout.fillWidth: true
            text: root.service.currentName || Tr.tr("VPN FortiClient")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
            elide: Text.ElideRight
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.rightMargin: Tokens.padding.extraSmall
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: root.service.connected ? "verified_user" : "remove_moderator"
            fill: root.service.connected ? 1 : 0
            color: root.service.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: root.service.statusText
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.medium
            }

            StyledText {
                visible: root.service.connected && root.service.vpnIp.length > 0
                text: root.service.vpnIp
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.mono.small
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.rightMargin: Tokens.padding.extraSmall
        visible: root.service.lastError.length > 0 && !root.service.otpOpen
        text: root.service.lastError
        color: Colours.palette.m3error
        font: Tokens.font.body.small
        wrapMode: Text.Wrap
    }

    TextButton {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        Layout.rightMargin: Tokens.padding.extraSmall
        Layout.minimumHeight: Tokens.font.body.medium.pointSize + Tokens.padding.medium * 2
        inactiveColour: root.service.connected ? Colours.palette.m3errorContainer : Colours.palette.m3primary
        inactiveOnColour: root.service.connected ? Colours.palette.m3onErrorContainer : Colours.palette.m3onPrimary
        text: root.service.busy ? root.service.statusText : (root.service.connected ? Tr.tr("Disconnect") : Tr.tr("Connect"))
        enabled: !root.service.busy

        onClicked: {
            if (root.service.connected)
                root.service.disconnect();
            else
                root.startConnect();
        }
    }
}
