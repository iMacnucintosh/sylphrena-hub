pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Sylphrena.Config
import Sylphrena.I18n
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services

// Shown in the extension's card in Nexus → Extensions: where the connections are, and export /
// import of all of them (to move them to another PC with this same extension).
ColumnLayout {
    id: root

    required property var ext
    required property var service

    property bool exportOpen: false
    property bool withSecrets: false

    readonly property bool passphraseOk: !root.withSecrets || (passField.text.length >= 8 && passField.text === pass2Field.text)

    function resetExport(): void {
        root.exportOpen = false;
        root.withSecrets = false;
        passField.text = "";
        pass2Field.text = "";
    }

    function doExport(): void {
        if (!root.passphraseOk)
            return;
        root.service.exportConnections(root.withSecrets, passField.text);
        root.resetExport();
    }

    function doImport(): void {
        if (importPassField.text.length === 0)
            return;
        root.service.importFile(root.service.importPath, importPassField.text);
        importPassField.text = "";
    }

    spacing: Tokens.spacing.medium

    // Only when something is wrong
    StyledText {
        Layout.fillWidth: true
        visible: !root.service.helperInstalled
        text: Tr.tr("The FortiClient helper is not installed: install the extension in Nexus → Extensions")
        color: Colours.palette.m3error
        font: Tokens.font.label.small
        wrapMode: Text.Wrap
    }

    // ---- Export / import ----------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        StyledText {
            Layout.fillWidth: true
            text: Tr.tr("Backup")
            font: Tokens.font.label.medium
        }

        IconTextButton {
            isRound: true
            type: IconTextButton.Tonal
            horizontalPadding: Tokens.padding.large
            verticalPadding: Tokens.padding.small
            icon: "upload"
            text: Tr.tr("Export")
            disabled: root.service.transferBusy || root.service.connections.length === 0
            onClicked: root.exportOpen = !root.exportOpen
        }

        IconTextButton {
            isRound: true
            type: IconTextButton.Tonal
            horizontalPadding: Tokens.padding.large
            verticalPadding: Tokens.padding.small
            icon: "download"
            text: Tr.tr("Import")
            disabled: root.service.transferBusy || importPicker.busy
            onClicked: {
                root.resetExport();
                root.service.cancelImport();
                importPicker.open();
            }
        }
    }

    // Export options
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.exportOpen
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Include passwords and private keys")
                    font: Tokens.font.label.medium
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.withSecrets ? Tr.tr("The file is encrypted with a passphrase you will need to import it.") : Tr.tr("Without them the file can be shared safely; you type the passwords again after importing.")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }
            }

            StyledSwitch {
                Layout.alignment: Qt.AlignVCenter
                checked: root.withSecrets
                onToggled: root.withSecrets = checked
            }
        }

        StyledTextField {
            id: passField

            Layout.fillWidth: true
            visible: root.withSecrets
            placeholderText: Tr.tr("Passphrase (at least 8 characters)")
            leadingIcon: "key"
            echoMode: TextInput.Password
            onAccepted: pass2Field.forceActiveFocus()
        }

        StyledTextField {
            id: pass2Field

            Layout.fillWidth: true
            visible: root.withSecrets
            placeholderText: Tr.tr("Repeat the passphrase")
            leadingIcon: "key"
            echoMode: TextInput.Password
            onAccepted: root.doExport()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Item {
                Layout.fillWidth: true
            }

            TextButton {
                isRound: true
                type: TextButton.Tonal
                horizontalPadding: Tokens.padding.large
                verticalPadding: Tokens.padding.small
                text: Tr.trCtx("Cancel", "button")
                onClicked: root.resetExport()
            }

            TextButton {
                isRound: true
                horizontalPadding: Tokens.padding.large
                verticalPadding: Tokens.padding.small
                disabled: !root.passphraseOk
                text: Tr.tr("Save to Downloads")
                onClicked: root.doExport()
            }
        }
    }

    // Passphrase of an encrypted export
    RowLayout {
        Layout.fillWidth: true
        visible: root.service.importNeedsPassphrase
        spacing: Tokens.spacing.small

        StyledTextField {
            id: importPassField

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
                importPassField.text = "";
                root.service.cancelImport();
            }
        }

        TextButton {
            isRound: true
            horizontalPadding: Tokens.padding.large
            verticalPadding: Tokens.padding.small
            disabled: importPassField.text.length === 0 || root.service.transferBusy
            text: Tr.tr("Import")
            onClicked: root.doImport()
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: text.length > 0
        text: root.service.transferBusy ? Tr.tr("Working…") : root.service.transferMessage
        color: root.service.transferFailed ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
        wrapMode: Text.WordWrap
    }

    // The result of the last export / import is not worth keeping on screen
    Timer {
        interval: 8000
        running: root.service.transferMessage.length > 0 && !root.service.transferBusy && !root.service.importNeedsPassphrase
        onTriggered: root.service.transferMessage = ""
    }

    FileDialog {
        id: importPicker

        title: Tr.tr("Select a FortiClient export")
        filterLabel: Tr.tr("FortiClient exports (.json, .json.enc)")
        filters: ["json", "enc"]
        onAccepted: path => root.service.importFile(path, "")
    }
}
