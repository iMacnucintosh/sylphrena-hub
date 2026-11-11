pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Non-Steam shortcuts (shortcuts.vdf) + Hidden collection via steam-nonsteam.py.
QtObject {
    id: root

    required property var host

    readonly property string nonSteamScript: `${root.host.ext.dir}/scripts/steam-nonsteam.py`

    function loadNonSteam(): void {
        if (!root.host.enabled)
            return;
        const args = ["python3", root.nonSteamScript];
        if (root.host.resolvedSteamId)
            args.push("--steamid", root.host.resolvedSteamId);
        nonSteamProc.command = args;
        nonSteamProc.running = true;
    }

    readonly property Process nonSteamProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text || "{}");
                    // Back-compat if script still returns a bare array
                    if (Array.isArray(data)) {
                        root.host.nonSteamGames = data;
                        root.host.hiddenAppIds = [];
                    } else {
                        root.host.nonSteamGames = Array.isArray(data.nonSteam) ? data.nonSteam : [];
                        root.host.hiddenAppIds = (data.hiddenAppIds || []).map(id => String(id));
                        root.host.applyHiddenFilter();
                    }
                } catch (e) {
                    console.warn(`Steam local library parse failed: ${e}`);
                    root.host.nonSteamGames = [];
                    root.host.hiddenAppIds = [];
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length)
                    console.warn(`steam-nonsteam.py: ${text.trim()}`);
            }
        }
    }
}
