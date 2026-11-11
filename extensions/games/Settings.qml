import QtQuick
import QtQuick.Layouts
import Quickshell.Io
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

    // What is installed on this machine (scripts/steam-nonsteam.py --status): the extension only looks
    property var found: ({})

    Process {
        running: true
        command: ["python3", `${root.ext.dir}/scripts/steam-nonsteam.py`, "--status"]
        stdinEnabled: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.found = JSON.parse(text);
                } catch (e) {
                    root.found = {};
                }
            }
        }
    }

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

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.medium
        text: Tr.tr("On this computer")
        font: Tokens.font.title.small
    }

    Repeater {
        model: [
            {
                key: "steam",
                label: Tr.tr("Steam"),
                hint: Tr.tr("Not found. Install Steam and sign in once.")
            },
            {
                key: "millennium",
                label: Tr.tr("Millennium"),
                hint: Tr.tr("Optional. A Steam client mod; without it everything else still works.")
            },
            {
                key: "playtimes",
                label: Tr.tr("Non-Steam Playtimes plugin"),
                hint: Tr.tr("Optional. Add it in Millennium to count the play time of games outside Steam.")
            }
        ]

        RowLayout {
            id: req

            required property var modelData
            readonly property bool ok: root.found[modelData.key] === true

            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: req.ok ? "check_circle" : "radio_button_unchecked"
                color: req.ok ? Colours.palette.m3primary : Colours.palette.m3outline
                fill: req.ok ? 1 : 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: req.modelData.label
                    font: Tokens.font.body.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !req.ok
                    text: req.modelData.hint
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
