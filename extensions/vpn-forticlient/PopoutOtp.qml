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

    readonly property bool shouldBeVisible: root.popouts.currentName === "vpnOtp"

    width: 320
    spacing: Tokens.spacing.medium

    function closeDialog(): void {
        root.service.cancelOtp();
        otpField.text = "";
        // Return to the VPN status popout (same pattern as Wi‑Fi password → network)
        if (root.popouts.currentName === "vpnOtp")
            root.popouts.currentName = "vpn";
    }

    function submit(): void {
        const token = otpField.text.trim();
        if (token.length === 0)
            return;
        root.service.connectWithOtp(token);
        otpField.text = "";
        if (root.popouts.currentName === "vpnOtp")
            root.popouts.currentName = "vpn";
    }

    visible: shouldBeVisible
    focus: shouldBeVisible

    Keys.onEscapePressed: closeDialog()

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            otpField.text = "";
            Qt.callLater(() => otpField.forceActiveFocus());
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "vpn_lock"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.large
            fill: 1
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: root.service.currentName || Tr.tr("VPN FortiClient")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }

            StyledText {
                text: Tr.tr("Enter your MFA OTP to connect")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }

    StyledTextField {
        id: otpField

        Layout.fillWidth: true
        placeholderText: Tr.tr("6-digit OTP")
        inputMethodHints: Qt.ImhDigitsOnly
        maximumLength: 12
        font: Tokens.font.mono.large
        horizontalAlignment: Text.AlignHCenter

        Keys.onReturnPressed: root.submit()
        Keys.onEnterPressed: root.submit()
    }

    StyledText {
        visible: root.service.lastError.length > 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.service.lastError
        color: Colours.palette.m3error
        font: Tokens.font.body.small
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        TextButton {
            Layout.fillWidth: true
            Layout.minimumHeight: Tokens.font.body.medium.pointSize + Tokens.padding.medium * 2
            inactiveColour: Colours.palette.m3secondaryContainer
            inactiveOnColour: Colours.palette.m3onSecondaryContainer
            text: Tr.trCtx("Cancel", "button")
            onClicked: root.closeDialog()
        }

        TextButton {
            Layout.fillWidth: true
            Layout.minimumHeight: Tokens.font.body.medium.pointSize + Tokens.padding.medium * 2
            inactiveColour: Colours.palette.m3primary
            inactiveOnColour: Colours.palette.m3onPrimary
            text: Tr.tr("Connect")
            enabled: otpField.text.trim().length > 0 && !root.service.busy
            onClicked: root.submit()
        }
    }
}
