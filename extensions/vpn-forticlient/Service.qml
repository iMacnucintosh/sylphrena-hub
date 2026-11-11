import QtQuick
import Quickshell
import Quickshell.Io
import Sylphrena
import Sylphrena.Config
import Sylphrena.I18n
import Sylphrena.Services
import qs.services
import qs.utils

// FortiClient (openfortivpn) connections. This extension contributes a VPN provider *type*
// (manifest `vpnProviderType`): every FortiClient connection is an entry of the VPN providers of the
// config (Nexus → Network, `type: "ext:vpn-forticlient"`), whose `options` hold its settings. The
// password never goes to shell.json: it lives in ~/.config/sylphrena/vpn/<id>.conf (mode 600), the
// openfortivpn file this service generates from `options` + password. The tunnel runs through the
// root helper of helper/sylphrena-fortivpn (installed with the extension: manifest `system`).
Scope {
    id: root

    // Injected by the base (services/Extensions.qml)
    required property var ext

    readonly property string typeId: `ext:${root.ext.id}`
    readonly property string helper: "/usr/local/sbin/sylphrena-fortivpn"
    readonly property string connDir: `${Quickshell.env("HOME")}/.config/sylphrena/vpn`
    // Until checked (test -x) nothing calls the helper
    property bool helperInstalled: false

    // Connections of this type, in the order of the provider list
    readonly property var connections: GlobalConfig.utilities.vpn.provider.values.filter(p => p.type === root.typeId)
    // The connection the bar acts on: the one up, else the one selected in Nexus, else the first
    readonly property var current: root.connectionById(root.connected ? root.activeId : "") ?? root.connectionById(root.pendingId) ?? root.connectionById(GlobalConfig.utilities.vpn.selectedProvider) ?? root.connections[0] ?? null
    readonly property string currentName: root.current ? (root.current.displayName || root.current.name) : ""

    property bool connected: false
    property string vpnIp: ""
    // Connection id of the tunnel that is up (reported by the helper)
    property string activeId: ""
    // Connection id being connected (or waiting for its OTP)
    property string pendingId: ""
    property string statusText: Tr.trCtx("Disconnected", "vpn state")
    property bool busy: false
    property bool otpOpen: false
    property string lastError: ""
    property bool wasConnected: false
    property bool tearingDown: false

    readonly property bool connecting: busy && !connected
    readonly property bool disconnecting: busy && connected

    // Connection files waiting to be written: [{ id, payload, startArgs }] (startArgs: connect after)
    property var _writeQueue: []

    // ── Export / import (extension settings in Nexus → Extensions) ───────────
    readonly property string transferScript: `${root.ext.dir}/tools/transfer.py`
    // Emitted when an import added or updated connections (an import row in Nexus closes its page)
    signal imported

    property bool transferBusy: false
    property string transferMessage: ""
    property bool transferFailed: false
    // An encrypted export waiting for its passphrase
    property bool importNeedsPassphrase: false
    property string importPath: ""

    function connectionById(id: string): var {
        return id ? (root.connections.find(p => p.id === id) ?? null) : null;
    }

    function opt(conn: var, key: string, fallback: var): var {
        const v = conn?.options?.[key];
        return v === undefined || v === null || v === "" ? fallback : v;
    }

    function list(v: var): var {
        if (Array.isArray(v))
            return v.map(x => String(x).trim()).filter(x => x.length > 0);
        return String(v ?? "").split(/[\s,]+/).filter(x => x.length > 0);
    }

    function needsOtp(conn: var): bool {
        return root.opt(conn, "auth", "password") === "otp";
    }

    // Called by the base just before the extension is disabled from Nexus: stop the tunnel and clear
    // DNS/hosts. Detached, because this service is destroyed right after.
    function aboutToDisable(): void {
        Quickshell.execDetached(["sudo", "-n", root.helper, "stop"]);
        if (GlobalConfig.utilities.toasts.vpnChanged)
            Toaster.toast(Tr.tr("VPN FortiClient"), Tr.tr("Extension disabled"), "shield");
    }

    function refreshStatus(): void {
        // While connect/disconnect is in flight the status is stale by definition; the process
        // onExited handler refreshes at the end.
        if (connectProc.running || disconnectProc.running || writerProc.running || statusProc.running)
            return;
        if (!root.helperInstalled) {
            // Installed later from Nexus → Extensions: picked up by the next poll
            if (!helperCheck.running)
                helperCheck.running = true;
            return;
        }
        statusProc.running = true;
    }

    function onResumed(): void {
        if (!root.helperInstalled)
            return;
        // After sleep the SSL tunnel is usually dead while ppp still looks up: heal tears it down
        if (!healProc.running)
            healProc.running = true;
        resumeBurst.ticks = 0;
        resumeBurst.restart();
    }

    // ── Provider contract (manifest `vpnProviderType`) ─────────────────────────
    // The VPN of the base drives a connection through connect(conn) / disconnect() / toggle() and
    // reads connected / activeId / pendingId / busy / otpOpen (= needs authentication) / lastError.

    function connect(conn: var): void {
        const c = conn ?? root.current;
        if (root.busy || root.connected)
            return;
        root.lastError = "";
        if (!root.helperInstalled) {
            if (!helperCheck.running)
                helperCheck.running = true;
            root.lastError = Tr.tr("The FortiClient helper is not installed: install the extension in Nexus → Extensions");
            return;
        }
        if (!c) {
            root.lastError = Tr.tr("No FortiClient connection: add one in Nexus → Network");
            return;
        }
        root.pendingId = c.id;
        if (root.needsOtp(c))
            root.otpOpen = true;
        else
            root.start(c, "");
    }

    function toggle(): void {
        if (root.busy)
            return;
        if (root.connected)
            root.disconnect();
        else
            root.connect(null);
    }

    // Kept for the bar popouts
    function requestOtp(): void {
        root.connect(null);
    }

    function cancelOtp(): void {
        root.otpOpen = false;
        root.lastError = "";
        if (!root.busy)
            root.pendingId = "";
    }

    function connectWithOtp(otp: string): void {
        const token = (otp || "").replace(/\s+/g, "");
        const c = root.connectionById(root.pendingId);
        if (token.length === 0 || root.busy || !c)
            return;
        root.otpOpen = false;
        root.start(c, token);
    }

    function start(conn: var, otp: string): void {
        const args = ["sudo", "-n", root.helper, "start", conn.id];
        if (otp)
            args.push("--otp", otp);
        const health = String(root.opt(conn, "healthHost", "")).trim();
        if (health)
            args.push("--health", health);
        const dns = root.list(root.opt(conn, "dns", []));
        if (dns.length)
            args.push("--dns", dns.join(","));
        const domains = root.list(root.opt(conn, "domains", []));
        if (domains.length)
            args.push("--domains", domains.join(","));
        const hosts = root.list(root.opt(conn, "hosts", []));
        if (hosts.length)
            args.push("--hosts", hosts.join(","));

        root.pendingId = conn.id;
        root.busy = true;
        root.lastError = "";
        root.statusText = Tr.trCtx("Connecting…", "vpn state");
        // Regenerate the connection file first: `options` may have changed by hand in shell.json
        root._enqueueWrite(conn.id, root.buildConf(conn.options ?? {}, root.readPassword(conn.id)), args);
    }

    function disconnect(): void {
        if (root.busy || !root.connected)
            return;
        root.busy = true;
        root.statusText = Tr.trCtx("Disconnecting…", "vpn state");
        disconnectProc.running = true;
    }

    function clearRuntimeState(): void {
        root.connected = false;
        root.vpnIp = "";
        root.activeId = "";
        root.pendingId = "";
        root.busy = false;
        root.wasConnected = false;
        root.otpOpen = false;
        root.tearingDown = false;
        root.statusText = Tr.trCtx("Disconnected", "vpn state");
    }

    // ── Connection files (the only place with the password) ─────────────────────

    function confPath(id: string): string {
        return `${root.connDir}/${id}.conf`;
    }

    function readPassword(id: string): string {
        if (!/^[A-Za-z0-9_-]+$/.test(id))
            return "";
        secretReader.path = root.confPath(id);
        secretReader.reload();
        const text = secretReader.text() || "";
        for (const raw of text.split("\n")) {
            const m = raw.match(/^\s*password\s*=\s?(.*)$/);
            if (m)
                return m[1];
        }
        return "";
    }

    function buildConf(o: var, password: string): string {
        const clean = v => String(v ?? "").replace(/[\r\n]/g, "").trim();
        const lines = ["# Generated by Sylphrena from Nexus → Network. Edit the connection there."];
        const add = (key, value) => {
            const v = clean(value);
            if (v.length > 0)
                lines.push(`${key} = ${v}`);
        };
        add("host", o.host);
        add("port", o.port || "443");
        add("username", o.username);
        if (password)
            lines.push(`password = ${String(password).replace(/[\r\n]/g, "")}`);
        add("realm", o.realm);
        add("user-cert", o.userCert);
        add("user-key", o.userKey);
        for (const cert of root.list(o.trustedCert))
            add("trusted-cert", cert);
        lines.push("set-routes = 1");
        lines.push(`set-dns = ${o.setDns === false ? 0 : 1}`);
        if (o.halfInternetRoutes)
            lines.push("half-internet-routes = 1");
        if (o.legacyTls)
            lines.push("seclevel-1 = 1");
        lines.push("persistent = 0");
        return lines.join("\n") + "\n";
    }

    // Write ~/.config/sylphrena/vpn/<id>.conf (dir 700, file 600). The text goes through stdin, so the
    // password is never on a command line nor in a file with wider permissions.
    function writeConnection(id: string, options: var, password: string): void {
        root._enqueueWrite(id, root.buildConf(options ?? {}, password ?? ""), null);
    }

    function _enqueueWrite(id: string, payload: string, startArgs: var): void {
        if (!/^[A-Za-z0-9_-]+$/.test(id))
            return;
        root._writeQueue = [...root._writeQueue, { id, payload, startArgs }];
        root._pumpWrites();
    }

    function _pumpWrites(): void {
        if (writerProc.running || root._writeQueue.length === 0)
            return;
        const job = root._writeQueue[0];
        root._writeQueue = root._writeQueue.slice(1);
        writerProc._job = job;
        writerProc._payload = job.payload;
        writerProc.command = ["sh", "-c", 'umask 077; mkdir -p "$1" && chmod 700 "$1" && cat > "$2.tmp" && mv -f "$2.tmp" "$2"', "sh", root.connDir, root.confPath(job.id)];
        writerProc.stdinEnabled = true;
        writerProc.running = true;
    }

    // Export every FortiClient connection to the Downloads folder. With secrets (password and client
    // key) the file is encrypted with the passphrase; without, it carries neither.
    function exportConnections(secrets: bool, passphrase: string): void {
        const conns = root.connections.map(p => ({
                    id: p.id,
                    name: p.displayName || p.name,
                    options: p.options ?? {}
                }));
        root._runTransfer("export", {
            connections: conns,
            secrets: secrets,
            passphrase: secrets ? passphrase : ""
        });
    }

    function importFile(path: string, passphrase: string): void {
        root.importPath = path;
        root._runTransfer("import", {
            path: path,
            passphrase: passphrase ?? ""
        });
    }

    function cancelImport(): void {
        root.importNeedsPassphrase = false;
        root.importPath = "";
        root.transferMessage = "";
    }

    function _runTransfer(cmd: string, request: var): void {
        if (transferProc.running)
            return;
        root.transferBusy = true;
        root.transferFailed = false;
        root.transferMessage = "";
        transferProc._payload = JSON.stringify(request);
        transferProc._cmd = cmd;
        transferProc.command = ["python3", root.transferScript, cmd];
        transferProc.stdinEnabled = true;
        transferProc.running = true;
    }

    function _transferError(msg: string): string {
        switch (msg) {
        case "the passphrase must have at least 8 characters":
            return Tr.tr("The passphrase must have at least 8 characters");
        case "there are no FortiClient connections to export":
            return Tr.tr("There are no FortiClient connections to export");
        case "wrong passphrase or damaged file":
            return Tr.tr("Wrong passphrase or damaged file");
        case "not a FortiClient export":
            return Tr.tr("This file is not a FortiClient export");
        case "this export comes from a newer version of the extension":
            return Tr.tr("This export comes from a newer version of the extension");
        case "the file has no connections":
            return Tr.tr("The file has no connections");
        case "cannot read the file":
            return Tr.tr("Cannot read the file");
        }
        return msg;
    }

    // Add the imported connections, or update the ones with the same name. A connection exported
    // without its password keeps the password it already had here.
    function _applyImport(list: var): void {
        let added = 0;
        let updated = 0;
        for (const c of list) {
            const data = {
                name: c.name,
                displayName: c.name,
                type: root.typeId,
                options: c.options
            };
            const idx = VPN.providers.findIndex(p => p.type === root.typeId && (p.displayName || p.name) === c.name);
            let id;
            if (idx >= 0) {
                id = VPN.providers[idx].id;
                VPN.updateProvider(idx, data);
                updated++;
            } else {
                id = VPN.addProvider(data);
                added++;
            }
            root.writeConnection(id, c.options, c.password || root.readPassword(id));
        }
        root.transferMessage = Tr.tr("Imported: %1 new, %2 updated").arg(added).arg(updated);
        root.imported();
        if (GlobalConfig.utilities.toasts.vpnChanged)
            Toaster.toast(Tr.tr("VPN FortiClient"), root.transferMessage, "download");
    }

    // The connection was deleted from Nexus: drop its file (and the tunnel if it is the one up), and
    // the certificate copies this extension made when importing it (never files the user owns)
    function forget(id: string, options: var): void {
        if (!/^[A-Za-z0-9_-]+$/.test(id))
            return;
        if (root.connected && root.activeId === id)
            root.disconnect();
        const rm = ["rm", "-rf", "--", root.confPath(id)];
        for (const key of ["userCert", "userKey"]) {
            const path = String(options?.[key] ?? "");
            const base = `${root.connDir}/certs/`;
            if (!path.startsWith(base) || path.includes(".."))
                continue;
            const end = path.indexOf("/", base.length);
            if (end > base.length)
                rm.push(path.slice(0, end));
        }
        Quickshell.execDetached(rm);
    }

    function applyStatus(out: string): void {
        const parts = (out || "").trim().split("|");
        const nowConnected = parts[0] === "connected";
        // A transition is owned by its process; ignore status that raced with it
        if (connectProc.running || disconnectProc.running || writerProc.running)
            return;
        const dropped = root.wasConnected && !nowConnected && !root.busy;

        root.connected = nowConnected;
        root.vpnIp = nowConnected ? (parts[1] || "") : "";
        root.activeId = nowConnected ? (parts[2] || "") : "";
        if (!root.otpOpen)
            root.pendingId = "";
        root.statusText = nowConnected ? Tr.tr("Connected · %1").arg(root.vpnIp) : Tr.trCtx("Disconnected", "vpn state");
        root.busy = false;
        root.wasConnected = nowConnected;

        if (dropped && GlobalConfig.utilities.toasts.vpnChanged)
            Toaster.toast(Tr.tr("VPN FortiClient"), Tr.tr("The VPN connection dropped"), "gpp_bad");
    }

    FileView {
        id: secretReader

        blockAllReads: true
        printErrors: false
    }

    Process {
        id: writerProc

        property string _payload: ""
        property var _job: null

        stdinEnabled: true
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.warn(`vpn-forticlient: ${text.trim()}`);
            }
        }
        onStarted: {
            writerProc.write(writerProc._payload);
            writerProc._payload = "";
            writerProc.stdinEnabled = false;
        }
        onExited: code => {
            const args = writerProc._job?.startArgs ?? null;
            writerProc._job = null;
            Qt.callLater(root._pumpWrites);
            if (code !== 0)
                console.warn("vpn-forticlient: could not write a connection file");
            if (!args)
                return;
            if (code !== 0) {
                root.busy = false;
                root.pendingId = "";
                root.lastError = Tr.tr("Could not write VPN config");
                root.refreshStatus();
                return;
            }
            connectProc.command = args;
            connectProc.running = true;
        }
    }

    Process {
        id: transferProc

        property string _payload: ""
        property string _cmd: ""

        stdinEnabled: true
        onStarted: {
            transferProc.write(transferProc._payload);
            transferProc._payload = "";
            transferProc.stdinEnabled = false;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root.transferBusy = false;
                let r;
                try {
                    r = JSON.parse(text);
                } catch (e) {
                    r = { ok: false, error: text.trim() || `${e}` };
                }
                if (r.needsPassphrase) {
                    root.importNeedsPassphrase = true;
                    root.transferMessage = Tr.tr("This file is encrypted: enter its passphrase");
                    return;
                }
                if (!r.ok) {
                    root.transferFailed = true;
                    root.transferMessage = root._transferError(r.error ?? "");
                    return;
                }
                if (transferProc._cmd === "export") {
                    root.transferMessage = Tr.tr("Saved to %1").arg(Paths.shortenHome(r.path));
                    if (GlobalConfig.utilities.toasts.vpnChanged)
                        Toaster.toast(Tr.tr("VPN FortiClient"), root.transferMessage, "upload");
                } else {
                    root.importNeedsPassphrase = false;
                    root.importPath = "";
                    root._applyImport(r.connections ?? []);
                }
            }
        }
    }

    Process {
        id: helperCheck

        command: ["test", "-x", root.helper]
        onExited: code => {
            root.helperInstalled = code === 0;
            if (root.helperInstalled)
                root.refreshStatus();
        }
    }

    Process {
        id: statusProc

        command: [root.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }
    }

    Process {
        id: healProc

        command: ["sudo", "-n", root.helper, "heal"]
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }
        onExited: root.refreshStatus()
    }

    Process {
        id: connectProc

        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t.length > 0)
                    root.lastError = t.split("\n").pop().replace(/^sylphrena-fortivpn:\s*/, "");
            }
        }
        onExited: code => {
            if (code === 0) {
                root.lastError = "";
                if (GlobalConfig.utilities.toasts.vpnChanged)
                    Toaster.toast(Tr.tr("VPN FortiClient"), Tr.tr("Connected to %1").arg(root.currentName), "vpn_lock");
            } else {
                if (code === 3)
                    root.lastError = Tr.tr("Login failed (user / password / OTP / certificate).");
                else if (!root.lastError || root.lastError.includes("password is required"))
                    root.lastError = Tr.tr("Could not start the VPN tunnel (code %1).").arg(code);
                if (GlobalConfig.utilities.toasts.vpnChanged)
                    Toaster.toast(Tr.tr("VPN FortiClient"), root.lastError, "gpp_bad");
            }
            root.busy = false;
            root.refreshStatus();
        }
    }

    Process {
        id: disconnectProc

        command: ["sudo", "-n", root.helper, "stop"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: () => {
            if (GlobalConfig.utilities.toasts.vpnChanged)
                Toaster.toast(Tr.tr("VPN FortiClient"), Tr.tr("VPN disconnected"), "shield");
            // A manual disconnect is not a drop: the next status must not warn "VPN dropped"
            root.wasConnected = false;
            root.connected = false;
            root.busy = false;
            root.refreshStatus();
        }
    }

    Timer {
        // Connected/busy: catch drops quickly; idle: cheap heartbeat
        interval: root.connected || root.busy ? 8000 : 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: resumeBurst

        property int ticks: 0

        interval: 1500
        repeat: true
        onTriggered: {
            root.refreshStatus();
            resumeBurst.ticks++;
            if (resumeBurst.ticks >= 6)
                resumeBurst.stop();
        }
    }

    Connections {
        target: SessionManager

        function onResumed(): void {
            root.onResumed();
        }
    }

    Component.onCompleted: helperCheck.running = true
}
