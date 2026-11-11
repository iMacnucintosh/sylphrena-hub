import QtQuick
import QtQuick.Layouts
import Sylphrena.Config
import Sylphrena.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Settings of the Games extension (Nexus → Extensions): Steam API key, Steam ID, auto refresh.
ColumnLayout {
    id: root

    // Injected by the base
    required property var ext
    required property var service

    property bool keyVisible: false

    spacing: Tokens.spacing.small

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Steam API key")
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("From steamcommunity.com/dev/apikey")
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        StyledTextField {
            Layout.preferredWidth: Tokens.sizes.nexus.textFieldWidth
            Layout.maximumWidth: root.width / 2
            Layout.alignment: Qt.AlignVCenter
            verticalPadding: Tokens.padding.small
            echoMode: root.keyVisible ? TextInput.Normal : TextInput.Password
            text: root.service.apiKey
            placeholderText: Tr.tr("API key")
            onEditingFinished: root.service.setApiKey(text)
        }

        IconButton {
            Layout.alignment: Qt.AlignVCenter
            icon: root.keyVisible ? "visibility_off" : "visibility"
            type: IconButton.Text
            isRound: true
            onClicked: root.keyVisible = !root.keyVisible
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Steam ID")
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("SteamID64, vanity name, or profile URL")
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        StyledTextField {
            Layout.preferredWidth: Tokens.sizes.nexus.textFieldWidth
            Layout.maximumWidth: root.width / 2
            Layout.alignment: Qt.AlignVCenter
            verticalPadding: Tokens.padding.small
            text: root.service.steamIdInput
            placeholderText: Tr.tr("Steam ID or vanity")
            onEditingFinished: root.service.setSteamId(text)
        }
    }

    SpinSettingRow {
        label: Tr.tr("Auto refresh")
        subtext: Tr.tr("Minutes between automatic Steam updates")
        value: root.service.refreshMinutes
        from: 1
        to: 180
        stepSize: 1
        onMoved: v => root.service.setRefreshMinutes(v)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Item {
            Layout.fillWidth: true
        }

        IconButton {
            isRound: true
            icon: "refresh"
            type: IconButton.Text
            font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
            padding: Tokens.padding.small
            enabled: root.service.configured
            onClicked: root.service.reload()
        }

        StyledText {
            text: Tr.tr("Refresh now")
            font: Tokens.font.label.small
            color: Colours.palette.m3outline
        }
    }
}
