pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Service of the Tasks extension. Persisted in ~/.local/state/sylphrena/tasks.json. Disabling the
// extension only unloads it: the tasks are kept.
Scope {
    id: root

    // Injected by the base (services/Extensions.qml)
    required property var ext

    // [{ id, text, done, createdAt, doneAt }] — newest pending first
    property var items: []
    property int nextId: 1
    property bool doneCollapsed: false
    property bool loaded: false
    // Id of the task just (un)checked: its new row plays an intro animation (cleared after a moment)
    property int lastToggledId: -1

    readonly property var pending: items.filter(t => !t.done)
    // Most recently completed first
    readonly property var done: items.filter(t => t.done).sort((a, b) => b.doneAt - a.doneAt)

    function add(text: string): void {
        const t = text.trim();
        if (!t)
            return;
        items = [{
                id: nextId++,
                text: t.slice(0, 500),
                done: false,
                createdAt: Date.now(),
                doneAt: 0
            }, ...items];
        persist();
    }

    function toggle(id: int): void {
        lastToggledId = id;
        toggledReset.restart();
        items = items.map(t => t.id === id ? {
                id: t.id,
                text: t.text,
                done: !t.done,
                createdAt: t.createdAt,
                doneAt: t.done ? 0 : Date.now()
            } : t);
        persist();
    }

    function remove(id: int): void {
        items = items.filter(t => t.id !== id);
        persist();
    }

    function clearDone(): void {
        items = items.filter(t => !t.done);
        persist();
    }

    function setDoneCollapsed(on: bool): void {
        doneCollapsed = on;
        persist();
    }

    function persist(): void {
        if (loaded)
            saveTimer.restart();
    }

    readonly property Timer toggledReset: Timer {
        interval: 1200
        onTriggered: root.lastToggledId = -1
    }

    readonly property Timer saveTimer: Timer {
        interval: 200
        onTriggered: storage.setText(JSON.stringify({
                items: root.items,
                nextId: root.nextId,
                doneCollapsed: root.doneCollapsed
            }, null, 2))
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/tasks.json`
        onLoaded: {
            try {
                const d = JSON.parse(text());
                const list = Array.isArray(d.items) ? d.items : [];
                root.items = list.filter(t => t && typeof t.text === "string").map((t, i) => ({
                            id: Number(t.id) || i + 1,
                            text: t.text,
                            done: !!t.done,
                            createdAt: Number(t.createdAt) || 0,
                            doneAt: Number(t.doneAt) || 0
                        }));
                root.nextId = Math.max(Number(d.nextId) || 1, ...root.items.map(t => t.id + 1), 1);
                root.doneCollapsed = !!d.doneCollapsed;
            } catch (e) {
                console.warn(`Unable to parse tasks.json: ${e}`);
            }
            root.loaded = true;
        }
        onLoadFailed: err => {
            root.loaded = true;
            if (err !== FileViewError.FileNotFound)
                console.warn(`Unable to load tasks.json: ${err}`);
        }
    }
}
