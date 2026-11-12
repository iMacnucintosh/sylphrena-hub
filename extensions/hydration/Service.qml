pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Sylphrena
import Sylphrena.Config
import Sylphrena.I18n
import qs.services
import qs.utils

// Service of the Hydration extension: the day's water intake, reminders (a notification with quick
// add buttons) and persistence (~/.local/state/sylphrena/hydration.json). Settings live in the
// extension's own config (ext.config); the service exists only while the extension is enabled.
Scope {
    id: root

    // Injected by the base (services/Extensions.qml)
    required property var ext

    readonly property int dailyGoalMl: Math.max(1, root.ext.config.get("dailyGoalMl", 3000))
    readonly property int reminderMinutes: Math.max(1, root.ext.config.get("reminderMinutes", 15))
    readonly property list<int> presets: [
        Math.max(1, root.ext.config.get("presetMl0", 20)),
        Math.max(1, root.ext.config.get("presetMl1", 83)),
        Math.max(1, root.ext.config.get("presetMl2", 250)),
        Math.max(1, root.ext.config.get("presetMl3", 500))
    ]
    // One line for the Nexus card when its settings are open
    readonly property string summary: Tr.tr("%1 ml · reminder every %2 min").arg(dailyGoalMl).arg(reminderMinutes)

    property string dateKey: ""
    property int drunkMl: 0
    property real lastAddAt: 0
    property real lastRemindAt: 0
    property int lastAddedMl: 0
    property bool loaded: false
    property var activeReminder: null

    readonly property real progress: Math.min(1, drunkMl / dailyGoalMl)
    readonly property int remainingMl: Math.max(0, dailyGoalMl - drunkMl)
    readonly property bool goalReached: drunkMl >= dailyGoalMl

    readonly property Timer saveTimer: Timer {
        interval: 200
        onTriggered: root.persist()
    }

    readonly property Timer dayTimer: Timer {
        // Midnight rollover; no need to wake every 30s
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.ensureToday()
    }

    readonly property Timer reminderTimer: Timer {
        // Reminder cadence is minutes; checking once a minute is enough
        interval: 60 * 1000
        running: root.loaded && !root.goalReached
        repeat: true
        onTriggered: root.maybeRemind()
    }

    function setDailyGoal(ml: int): void {
        root.ext.config.set("dailyGoalMl", Math.max(1, Math.round(ml)));
    }

    function setReminderMinutes(mins: int): void {
        root.ext.config.set("reminderMinutes", Math.max(1, Math.round(mins)));
    }

    function setPreset(index: int, ml: int): void {
        if (index >= 0 && index <= 3)
            root.ext.config.set(`presetMl${index}`, Math.max(1, Math.round(ml)));
    }

    function todayKey(): string {
        const d = new Date();
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, "0");
        const day = String(d.getDate()).padStart(2, "0");
        return `${y}-${m}-${day}`;
    }

    function ensureToday(): void {
        const key = root.todayKey();
        if (root.dateKey === key)
            return;
        root.dateKey = key;
        root.drunkMl = 0;
        root.lastAddedMl = 0;
        root.lastAddAt = Date.now();
        root.dismissReminder();
        root.schedulePersist();
    }

    function schedulePersist(): void {
        if (root.loaded)
            saveTimer.restart();
    }

    function persist(): void {
        if (!root.loaded)
            return;
        storage.setText(JSON.stringify({
                    dateKey: root.dateKey,
                    drunkMl: root.drunkMl,
                    lastAddAt: root.lastAddAt,
                    lastAddedMl: root.lastAddedMl,
                    lastRemindAt: root.lastRemindAt
                }));
    }

    function addMl(amount: int): void {
        root.ensureToday();
        const ml = Math.max(0, Math.round(amount));
        if (ml <= 0)
            return;
        root.drunkMl += ml;
        root.lastAddedMl = ml;
        root.lastAddAt = Date.now();
        root.dismissReminder();
        root.schedulePersist();
    }

    function removeMl(amount: int): void {
        root.ensureToday();
        const ml = Math.max(0, Math.round(amount));
        if (ml <= 0 || root.drunkMl <= 0)
            return;
        const removed = Math.min(ml, root.drunkMl);
        root.drunkMl -= removed;
        root.lastAddedMl = 0;
        root.lastAddAt = Date.now();
        root.dismissReminder();
        root.schedulePersist();
    }

    function undoLast(): void {
        if (root.lastAddedMl <= 0)
            return;
        root.ensureToday();
        root.drunkMl = Math.max(0, root.drunkMl - root.lastAddedMl);
        root.lastAddedMl = 0;
        root.lastAddAt = Date.now();
        root.schedulePersist();
    }

    function dismissReminder(): void {
        if (root.activeReminder) {
            try {
                root.activeReminder.close();
            } catch (e) {}
            root.activeReminder = null;
        }
    }

    function reminderStillOpen(): bool {
        const n = root.activeReminder;
        if (!n)
            return false;
        try {
            if (n.closed || !Notifs.list.includes(n)) {
                root.activeReminder = null;
                return false;
            }
            return !!n.popup;
        } catch (e) {
            root.activeReminder = null;
            return false;
        }
    }

    function maybeRemind(): void {
        if (root.goalReached)
            return;
        root.ensureToday();
        if (root.reminderStillOpen())
            return;

        const windowMs = root.reminderMinutes * 60000;
        const now = Date.now();
        if (now - (root.lastAddAt || now) < windowMs)
            return;
        if (root.lastRemindAt && now - root.lastRemindAt < windowMs)
            return;

        root.showReminder();
    }

    // `sylph ext hydration <command>` (contributes.commands in the manifest)
    function command(name: string, args: list<string>): string {
        if (name === "show") {
            root.showReminder();
            return "ok";
        }
        if (name === "add") {
            const ml = parseInt(args[0] ?? "", 10);
            if (!(ml > 0))
                return "error: usage: sylph ext hydration add <ml>";
            root.addMl(ml);
            return `${root.drunkMl} / ${root.dailyGoalMl} ml`;
        }
        if (name === "status")
            return `${root.drunkMl} / ${root.dailyGoalMl} ml`;
        return `error: unknown command ${name}`;
    }

    function showReminder(): void {
        root.dismissReminder();
        root.lastRemindAt = Date.now();

        const p0 = root.presets[0] || 20;
        const p1 = root.presets[1] || 83;
        const notif = Notifs.pushLocal({
                notificationId: "local:hydration",
                summary: Tr.tr("Time to drink water"),
                body: "",
                // The day's water as the notification's progress bar, with what was drunk and the goal at its ends
                // (Sylphrena ≥ 0.5.2)
                localProgress: root.dailyGoalMl > 0 ? Math.min(1, root.drunkMl / root.dailyGoalMl) : 0,
                progressFrom: `${root.drunkMl} ml`,
                progressTo: `${root.dailyGoalMl} ml`,
                appName: Tr.tr("Hydration"),
                appIcon: "",
                expireTimeout: Math.max(8000, GlobalConfig.notifs.defaultExpireTimeout),
                resident: false,
                actions: []
            });

        notif.actions = [
            {
                identifier: "add-small",
                text: `${p0} ml`,
                invoke: () => {
                    root.addMl(p0);
                    notif.close();
                }
            },
            {
                identifier: "add-sip",
                text: `${p1} ml`,
                invoke: () => {
                    root.addMl(p1);
                    notif.close();
                }
            }
        ];
        root.activeReminder = notif;
    }

    function restore(data: var): void {
        const key = root.todayKey();
        const savedKey = data?.dateKey || "";
        if (savedKey === key) {
            root.dateKey = key;
            root.drunkMl = Math.max(0, Number(data.drunkMl) || 0);
            root.lastAddAt = Number(data.lastAddAt) || Date.now();
            root.lastAddedMl = Math.max(0, Number(data.lastAddedMl) || 0);
            root.lastRemindAt = Number(data.lastRemindAt) || 0;
        } else {
            root.dateKey = key;
            root.drunkMl = 0;
            root.lastAddedMl = 0;
            root.lastAddAt = Date.now();
            root.lastRemindAt = 0;
        }
        root.loaded = true;
        root.schedulePersist();
    }

    // Disabling the extension destroys this service: close a pending reminder with it
    Component.onDestruction: dismissReminder()

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/hydration.json`
        onLoaded: {
            try {
                root.restore(JSON.parse(text()));
            } catch (e) {
                console.warn(`Unable to parse hydration.json: ${e}`);
                root.dateKey = root.todayKey();
                root.lastAddAt = Date.now();
                root.loaded = true;
                root.schedulePersist();
            }
        }
        onLoadFailed: err => {
            root.dateKey = root.todayKey();
            root.lastAddAt = Date.now();
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => root.persist());
            else
                console.warn(`Unable to load hydration.json: ${err}`);
        }
    }
}
