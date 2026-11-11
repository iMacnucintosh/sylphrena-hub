pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Activity poll / snapshot Processes + live clock. Snapshot payload goes on stdin
// (avoids ARG_MAX for large libraries).
QtObject {
    id: root

    required property var host

    property string _snapshotPayload: ""

    readonly property string activityScript: `${root.host.ext.dir}/scripts/steam-activity.py`

    function applyActivity(text: string): void {
        const raw = text || "{}";
        if (raw === root.host.lastActivityJson) {
            root.host.activityNow = Date.now() / 1000;
            return;
        }
        try {
            root.host.activity = JSON.parse(raw);
            root.host.lastActivityJson = raw;
            root.host.activityNow = Date.now() / 1000;
        } catch (e) {
            console.warn(`Steam activity parse failed: ${e}`);
        }
    }

    function logPlaytime(games: var): void {
        const list = Array.isArray(games) ? games : [];
        const rows = list.filter(game => game.playtimeForever > 0).map(game => [game.appId, game.playtimeForever, game.lastPlayed]);
        root._snapshotPayload = JSON.stringify(rows);
        snapshotProc.command = ["python3", root.activityScript, "snapshot"];
        snapshotProc.stdinEnabled = true;
        if (!snapshotProc.running)
            snapshotProc.running = true;
        else {
            // Restart so onStarted re-fires with the new payload
            snapshotProc.running = false;
            Qt.callLater(() => {
                snapshotProc.stdinEnabled = true;
                snapshotProc.running = true;
            });
        }
    }

    function startPollIfNeeded(): void {
        if (root.host.enabled && root.host.configured && !pollProc.running)
            pollProc.running = true;
    }

    // QtObject has no default property — nest IO as named properties (Brightness pattern).
    readonly property Timer pollTimer: Timer {
        // Active sessions: 45s; otherwise 2 min (python skips /proc walk if Steam is down)
        interval: Object.keys(root.host.activity.active ?? {}).length > 0 ? 45 * 1000 : 120 * 1000
        running: root.host.enabled && root.host.configured
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!pollProc.running)
                pollProc.running = true;
        }
    }

    readonly property Timer liveClock: Timer {
        interval: 30 * 1000
        running: root.host.enabled && Object.keys(root.host.activity.active ?? {}).length > 0
        repeat: true
        onTriggered: root.host.activityNow = Date.now() / 1000
    }

    readonly property Process pollProc: Process {
        command: ["python3", root.activityScript, "poll"]
        stdout: StdioCollector {
            onStreamFinished: root.applyActivity(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length)
                    console.warn(`steam-activity.py: ${text.trim()}`);
            }
        }
    }

    readonly property Process snapshotProc: Process {
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: root.applyActivity(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length)
                    console.warn(`steam-activity.py: ${text.trim()}`);
            }
        }
        onStarted: {
            snapshotProc.write(root._snapshotPayload || "[]");
            root._snapshotPayload = "";
            snapshotProc.stdinEnabled = false;
        }
    }
}
