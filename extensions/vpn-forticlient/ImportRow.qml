pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Sylphrena.Config
import Sylphrena.I18n
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.modules.nexus.common

// First row of Nexus → Network → Add provider → FortiClient (manifest `vpnProviderType.importer`):
// fill the connections from an export of this extension (Extensions card → Backup → Export).
ConnectedRect {
    id: root

    required property var ext
    required property var service
    // Leaves the Add provider page (set by the base)
    property var close: () => {}

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + Tokens.padding.medium * 2

    function doImport(): void {
        if (passField.text.length === 0)
            return;
        root.service.importFile(root.service.importPath, passField.text);
        passField.text = "";
    }

    // Nothing from an earlier export / import on screen
    Component.onCompleted: root.service.cancelImport()

    Connections {
        function onImported(): void {
            root.close();
        }

        target: root.service
    }

    ColumnLayout {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: "download"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
                fill: 1
            }

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Import from a file")
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            IconTextButton {
                Layout.alignment: Qt.AlignVCenter
                isRound: true
                horizontalPadding: Tokens.padding.large
                verticalPadding: Tokens.padding.small
                disabled: root.service.transferBusy || picker.busy
                icon: "folder_open"
                text: Tr.tr("Browse")
                onClicked: {
                    root.service.cancelImport();
                    picker.open();
                }
            }
        }

        // Encrypted export: its passphrase
        RowLayout {
            Layout.fillWidth: true
            visible: root.service.importNeedsPassphrase
            spacing: Tokens.spacing.small

            StyledTextField {
                id: passField

                Layout.fillWidth: true
                placeholderText: Tr.tr("Passphrase of the file")
                leadingIcon: "key"
                echoMode: TextInput.Password
                onAccepted: root.doImport()
            }

            TextButton {
                isRound: true
                type: TextButton.Tonal
                horizontalPadding: Tokens.padding.large
                verticalPadding: Tokens.padding.small
                text: Tr.trCtx("Cancel", "button")
                onClicked: {
                    passField.text = "";
                    root.service.cancelImport();
                }
            }

            TextButton {
                isRound: true
                horizontalPadding: Tokens.padding.large
                verticalPadding: Tokens.padding.small
                disabled: passField.text.length === 0 || root.service.transferBusy
                text: Tr.tr("Import")
                onClicked: root.doImport()
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.service.transferBusy ? Tr.tr("Working…") : root.service.transferMessage
            color: root.service.transferFailed ? Colours.palette.m3error : Colours.palette.m3outline
            font: Tokens.font.label.small
            wrapMode: Text.WordWrap
        }
    }

    FileDialog {
        id: picker

        title: Tr.tr("Select a FortiClient export")
        filterLabel: Tr.tr("FortiClient exports (.json, .json.enc)")
        filters: ["json", "enc"]
        onAccepted: path => root.service.importFile(path, "")
    }
}
