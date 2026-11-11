pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import Sylphrena.Config
import Sylphrena.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Fields of a FortiClient connection, shown by Nexus → Network → Add / Edit VPN provider when the
// FortiClient type is chosen (manifest `vpnProviderType.editor`). Contract with the page:
//   options / providerId (in), validate(): string, collectOptions(): var, commit(id) (stores the
//   password in the connection file, never in shell.json).
ColumnLayout {
    id: root

    // Injected by the base: the extension and its service (see services/Extensions.qml)
    required property var ext
    required property var service
    // The `options` of the connection being edited ({} for a new one) and its id ("" when new)
    property var options: ({})
    property string providerId: ""

    property bool showPassword: false

    function o(key: string, fallback: var): var {
        const v = root.options?.[key];
        return v === undefined || v === null ? fallback : v;
    }

    function joinList(v: var, sep: string): string {
        return Array.isArray(v) ? v.join(sep) : String(v ?? "");
    }

    function splitList(text: string): var {
        return text.split(/[\s,]+/).map(s => s.trim()).filter(s => s.length > 0);
    }

    // "10.0.0.1 intranet.example.com, 10.0.0.2 wiki.example.com" -> ["10.0.0.1=intranet.example.com", …]
    function parseHosts(text: string): var {
        const out = [];
        for (const part of text.split(/[,\n]+/)) {
            const bits = part.trim().split(/[\s=]+/).filter(s => s.length > 0);
            if (bits.length === 2)
                out.push(`${bits[0]}=${bits[1]}`);
            else if (bits.length > 0)
                out.push(part.trim());
        }
        return out;
    }

    function validate(): string {
        const ipv4 = /^(\d{1,3}\.){3}\d{1,3}$/;
        const host = /^[A-Za-z0-9][A-Za-z0-9.-]*$/;
        if (!hostField.text.trim())
            return Tr.tr("Host is required");
        if (portField.text.trim() && !/^\d+$/.test(portField.text.trim()))
            return Tr.tr("Port must be a number");
        for (const p of [certField.text.trim(), keyField.text.trim()])
            if (p && !p.startsWith("/"))
                return Tr.tr("Certificate paths must be absolute");
        const health = healthField.text.trim();
        if (health && !ipv4.test(health) && !host.test(health))
            return Tr.tr("Invalid health check host");
        if (root.splitList(dnsField.text).some(s => !ipv4.test(s)))
            return Tr.tr("DNS servers must be IPv4 addresses");
        if (root.splitList(domainsField.text).some(s => !/^~?[A-Za-z0-9][A-Za-z0-9.-]*$/.test(s)))
            return Tr.tr("Invalid DNS domain");
        for (const e of root.parseHosts(hostsField.text)) {
            const [ip, name] = e.split("=");
            if (!ipv4.test(ip ?? "") || !host.test(name ?? ""))
                return Tr.tr("Hosts entries are 'IP name', separated by commas");
        }
        return "";
    }

    function collectOptions(): var {
        return {
            host: hostField.text.trim(),
            port: portField.text.trim() || "443",
            realm: realmField.text.trim(),
            username: userField.text.trim(),
            auth: otpToggle.checked ? "otp" : "password",
            userCert: certField.text.trim(),
            userKey: keyField.text.trim(),
            trustedCert: trustedField.text.trim(),
            legacyTls: legacyToggle.checked,
            halfInternetRoutes: halfRoutesToggle.checked,
            healthHost: healthField.text.trim(),
            dns: root.splitList(dnsField.text),
            domains: root.splitList(domainsField.text),
            hosts: root.parseHosts(hostsField.text)
        };
    }

    function commit(id: string): void {
        root.service.writeConnection(id, root.collectOptions(), passField.text);
    }

    spacing: Tokens.spacing.large

    Component.onCompleted: {
        hostField.text = root.o("host", "");
        portField.text = root.o("port", "");
        realmField.text = root.o("realm", "");
        userField.text = root.o("username", "");
        otpToggle.checked = root.o("auth", "password") === "otp";
        certField.text = root.o("userCert", "");
        keyField.text = root.o("userKey", "");
        trustedField.text = root.o("trustedCert", "");
        legacyToggle.checked = !!root.o("legacyTls", false);
        halfRoutesToggle.checked = !!root.o("halfInternetRoutes", false);
        healthField.text = root.o("healthHost", "");
        dnsField.text = root.joinList(root.o("dns", []), ", ");
        domainsField.text = root.joinList(root.o("domains", []), ", ");
        hostsField.text = root.joinList(root.o("hosts", []), ", ").replace(/=/g, " ");
        if (root.providerId)
            passField.text = root.service.readPassword(root.providerId);
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        text: Tr.tr("The password is stored only in ~/.config/sylphrena/vpn/ (readable only by you), never in shell.json.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
        wrapMode: Text.WordWrap
    }

    StyledTextField {
        id: hostField

        Layout.fillWidth: true
        placeholderText: Tr.trCtx("Host", "vpn server hostname")
        leadingIcon: "dns"
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onAccepted: portField.forceActiveFocus()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledTextField {
            id: portField

            Layout.preferredWidth: Math.round(root.width * 0.32)
            Layout.minimumWidth: Tokens.sizes.nexus.smallTextFieldWidth
            placeholderText: Tr.trCtx("Port", "vpn server port")
            leadingIcon: "tag"
            inputMethodHints: Qt.ImhDigitsOnly
            onAccepted: realmField.forceActiveFocus()
        }

        StyledTextField {
            id: realmField

            Layout.fillWidth: true
            placeholderText: Tr.trCtx("Realm", "vpn authentication realm")
            leadingIcon: "domain"
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onAccepted: userField.forceActiveFocus()
        }
    }

    StyledTextField {
        id: userField

        Layout.fillWidth: true
        placeholderText: Tr.trCtx("Username", "vpn username")
        leadingIcon: "person"
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onAccepted: passField.forceActiveFocus()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        StyledTextField {
            id: passField

            Layout.fillWidth: true
            placeholderText: Tr.trCtx("Password", "vpn password")
            leadingIcon: "key"
            echoMode: root.showPassword ? T.TextField.Normal : T.TextField.Password
        }

        IconButton {
            Layout.alignment: Qt.AlignVCenter
            icon: root.showPassword ? "visibility_off" : "visibility"
            type: IconButton.Text
            isRound: true
            onClicked: root.showPassword = !root.showPassword
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            id: otpToggle

            first: true
            text: Tr.tr("Ask for a one-time code (OTP)")
            subtext: Tr.tr("Connecting opens the code dialog in the VPN icon of the bar")
        }

        ToggleRow {
            id: legacyToggle

            text: Tr.tr("Allow legacy TLS")
            subtext: Tr.tr("Needed by some older FortiGate servers (seclevel-1)")
        }

        ToggleRow {
            id: halfRoutesToggle

            last: true
            text: Tr.tr("Half-internet routes")
            subtext: Tr.tr("Routes 0.0.0.0/1 and 128.0.0.0/1 instead of replacing the default route")
        }
    }

    SectionHeader {
        text: Tr.tr("Certificate (optional)")
    }

    StyledTextField {
        id: certField

        Layout.fillWidth: true
        placeholderText: Tr.tr("Client certificate (PEM path)")
        leadingIcon: "badge"
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
    }

    StyledTextField {
        id: keyField

        Layout.fillWidth: true
        placeholderText: Tr.tr("Client key (PEM path)")
        leadingIcon: "vpn_key"
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
    }

    StyledTextField {
        id: trustedField

        Layout.fillWidth: true
        placeholderText: Tr.tr("Trusted server certificate (SHA-256)")
        supportingText: Tr.tr("Only if the server certificate is not trusted by the system")
        leadingIcon: "verified"
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
    }

    SectionHeader {
        text: Tr.tr("Network (optional)")
    }

    StyledTextField {
        id: healthField

        Layout.fillWidth: true
        placeholderText: Tr.tr("Health check host")
        supportingText: Tr.tr("A host inside the VPN that answers ping. If it stops answering (e.g. after suspend) the tunnel is torn down.")
        leadingIcon: "monitor_heart"
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
    }

    StyledTextField {
        id: dnsField

        Layout.fillWidth: true
        placeholderText: Tr.tr("DNS servers")
        supportingText: Tr.tr("Comma separated. Applied with systemd-resolved; without it the server's DNS is used.")
        leadingIcon: "dns"
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
    }

    StyledTextField {
        id: domainsField

        Layout.fillWidth: true
        placeholderText: Tr.tr("DNS domains")
        supportingText: Tr.tr("Domains resolved through the VPN, e.g. ~example.com")
        leadingIcon: "language"
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
    }

    StyledTextField {
        id: hostsField

        Layout.fillWidth: true
        placeholderText: Tr.tr("Hosts entries")
        supportingText: Tr.tr("'IP name' pairs, comma separated. Added to /etc/hosts while connected.")
        leadingIcon: "list_alt"
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
    }
}
