pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Sylphrena.Config
import Sylphrena.I18n
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    // Injected by the games tab (the extension's service)
    required property var service

    property string gameKey
    property var sessions: []
    property var dailyMinutes: ({}) // { "YYYY-MM-DD": minutes }
    property var markerTimes: [] // unix times highlighted with a dot (achievement unlocks)
    property real contentHeight: 4 * 44 + 3 * Tokens.spacing.small
    property int monthOffset: 0
    /// 0 = whole month; otherwise 1..daysInMonth filters the stats column.
    property int selectedDay: 0
    readonly property int maxMonthsBack: 24

    readonly property var qlocale: Qt.locale(Tr.locale.name)
    readonly property int firstDow: (qlocale.firstDayOfWeek ?? 1) % 7
    readonly property date monthStart: {
        const d = new Date();
        return new Date(d.getFullYear(), d.getMonth() + monthOffset, 1);
    }
    readonly property int daysInMonth: new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 0).getDate()
    readonly property int leading: (monthStart.getDay() - firstDow + 7) % 7
    readonly property real monthFrom: monthStart.getTime() / 1000
    readonly property real monthTo: new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 1).getTime() / 1000
    readonly property real selectedDayFrom: selectedDay > 0 ? new Date(monthStart.getFullYear(), monthStart.getMonth(), selectedDay).getTime() / 1000 : 0
    readonly property real selectedDayTo: selectedDay > 0 ? new Date(monthStart.getFullYear(), monthStart.getMonth(), selectedDay + 1).getTime() / 1000 : 0

    readonly property var monthSessions: sessions.filter(s => s.start >= monthFrom && s.start < monthTo)
    readonly property var dayMinutes: {
        const secs = new Array(daysInMonth).fill(0);
        for (const s of sessions) {
            let cur = Math.max(s.start, monthFrom);
            const end = Math.min(s.end, monthTo);
            while (cur < end) {
                const d = new Date(cur * 1000);
                const nextMidnight = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime() / 1000;
                const until = Math.min(nextMidnight, end);
                secs[d.getDate() - 1] += until - cur;
                cur = until;
            }
        }
        const prefix = `${monthStart.getFullYear()}-${String(monthStart.getMonth() + 1).padStart(2, "0")}-`;
        return secs.map((s, i) => Math.round(s / 60) + (dailyMinutes?.[prefix + String(i + 1).padStart(2, "0")] ?? 0));
    }
    readonly property var dayMarkers: {
        const out = new Array(daysInMonth).fill(0);
        for (const t of markerTimes)
            if (t >= monthFrom && t < monthTo)
                out[new Date(t * 1000).getDate() - 1]++;
        return out;
    }
    readonly property var cells: {
        const out = [];
        for (let i = 0; i < leading; i++)
            out.push(null);
        for (let d = 1; d <= daysInMonth; d++)
            out.push({
                day: d,
                minutes: dayMinutes[d - 1],
                markers: dayMarkers[d - 1]
            });
        return out;
    }

    // Sessions that overlap the selected calendar day (or the whole month).
    readonly property var filteredSessions: {
        if (selectedDay <= 0)
            return monthSessions;
        const from = selectedDayFrom;
        const to = selectedDayTo;
        return sessions.filter(s => s.start < to && s.end > from);
    }
    readonly property int totalMinutes: selectedDay > 0 ? (dayMinutes[selectedDay - 1] ?? 0) : dayMinutes.reduce((a, m) => a + m, 0)
    // Minutes on a day that came only from Steam playtime deltas (shell was
    // off) — no polled session rows, but the heatmap still has a value.
    readonly property int residualDayMinutes: {
        if (selectedDay <= 0)
            return 0;
        let tracked = 0;
        const from = selectedDayFrom;
        const to = selectedDayTo;
        for (const s of filteredSessions) {
            tracked += Math.max(0, Math.min(s.end, to) - Math.max(s.start, from));
        }
        return Math.max(0, totalMinutes - Math.round(tracked / 60));
    }
    readonly property int longestMinutes: {
        if (selectedDay <= 0)
            return monthSessions.reduce((m, s) => Math.max(m, Math.round((s.end - s.start) / 60)), 0);
        // One play block that day (0–1 polled sessions ± Steam residual): Total == Longest.
        if (filteredSessions.length <= 1)
            return totalMinutes;
        const from = selectedDayFrom;
        const to = selectedDayTo;
        let max = 0;
        for (const s of filteredSessions) {
            const secs = Math.min(s.end, to) - Math.max(s.start, from);
            max = Math.max(max, Math.round(secs / 60));
        }
        return Math.max(max, residualDayMinutes);
    }
    readonly property int sessionCount: {
        if (selectedDay <= 0)
            return monthSessions.length;
        // Count a synthetic session when Steam attributed playtime with no poll.
        return filteredSessions.length + (residualDayMinutes > 0 && filteredSessions.length === 0 ? 1 : 0);
    }
    readonly property int monthMarkers: dayMarkers.reduce((a, n) => a + n, 0)
    readonly property bool hasPlay: dayMinutes.reduce((a, m) => a + m, 0) > 0 || monthSessions.length > 0

    function selectDay(day: int): void {
        if (day <= 0 || day > daysInMonth)
            return;
        const mins = dayMinutes[day - 1] ?? 0;
        const marks = dayMarkers[day - 1] ?? 0;
        if (mins <= 0 && marks <= 0)
            return;
        selectedDay = selectedDay === day ? 0 : day;
    }

    onGameKeyChanged: {
        monthOffset = 0;
        selectedDay = 0;
    }
    onMonthOffsetChanged: selectedDay = 0

    readonly property real gap: Tokens.spacing.extraSmall
    readonly property real labelHeight: 14
    readonly property real cellSize: Math.floor((contentHeight - labelHeight - gap * 6) / 6)

    // Busiest day of the month: the shades are relative to it, so a month of long sessions still shows
    // which days were heavier (fixed hour thresholds turned every day into the darkest shade)
    readonly property int maxDayMinutes: dayMinutes.reduce((m, v) => Math.max(m, v), 0)
    readonly property int levels: 5

    function level(minutes: int): int {
        if (minutes <= 0 || maxDayMinutes <= 0)
            return 0;
        // Slightly curved so the light days do not all collapse into the first shade
        const frac = Math.pow(Math.min(1, minutes / maxDayMinutes), 0.8);
        return Math.max(1, Math.min(levels, Math.ceil(frac * levels)));
    }

    function levelColour(lvl: int): color {
        if (lvl <= 0)
            return Colours.palette.m3surfaceContainerHighest;
        return Qt.alpha(Colours.palette.m3primary, 0.2 + 0.8 * (lvl - 1) / (levels - 1));
    }

    implicitHeight: col.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.extraSmall
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "calendar_month"
                color: Colours.palette.m3tertiary
                fill: 1
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    const sameYear = root.monthStart.getFullYear() === new Date().getFullYear();
                    return Tr.tr("Activity in %1").arg(Tr.formatDateTime(root.monthStart, sameYear ? "MMMM" : "MMMM yyyy"));
                }
                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
                elide: Text.ElideRight
            }

            IconButton {
                Layout.topMargin: -Tokens.padding.extraSmall
                Layout.bottomMargin: -Tokens.padding.extraSmall
                type: IconButton.Text
                icon: "chevron_left"
                disabled: root.monthOffset <= -root.maxMonthsBack
                onClicked: root.monthOffset--
            }

            IconButton {
                Layout.topMargin: -Tokens.padding.extraSmall
                Layout.bottomMargin: -Tokens.padding.extraSmall
                type: IconButton.Text
                icon: "chevron_right"
                disabled: root.monthOffset >= 0
                onClicked: root.monthOffset++
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.contentHeight
            spacing: Tokens.spacing.medium

            Column {
                Layout.alignment: Qt.AlignTop
                spacing: root.gap

                Row {
                    spacing: root.gap

                    Repeater {
                        model: 7

                        StyledText {
                            required property int index

                            width: root.cellSize
                            height: root.labelHeight
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: root.qlocale.dayName((root.firstDow + index) % 7, Locale.NarrowFormat).toUpperCase()
                            font: Tokens.font.label.small
                            color: Colours.palette.m3outline
                        }
                    }
                }

                Grid {
                    columns: 7
                    spacing: root.gap

                    Repeater {
                        model: root.cells

                        Item {
                            id: cell

                            required property var modelData
                            required property int index

                            readonly property bool isToday: !!modelData && root.monthOffset === 0 && modelData.day === new Date().getDate()
                            readonly property bool isFuture: !!modelData && root.monthOffset === 0 && modelData.day > new Date().getDate()
                            readonly property bool isSelected: !!modelData && root.selectedDay === modelData.day
                            readonly property bool hasActivity: !!modelData && ((modelData.minutes ?? 0) > 0 || (modelData.markers ?? 0) > 0)
                            readonly property int lvl: modelData ? Math.max(root.level(modelData.minutes), modelData.markers > 0 ? 1 : 0) : 0

                            width: root.cellSize
                            height: root.cellSize

                            StyledRect {
                                anchors.fill: parent
                                visible: !!cell.modelData
                                radius: Tokens.rounding.small
                                color: root.levelColour(cell.lvl)
                                opacity: cell.isFuture ? 0.4 : (root.selectedDay > 0 && !cell.isSelected ? 0.55 : 1)
                                border.width: cell.isSelected ? 2 : (cell.isToday ? 2 : 0)
                                border.color: cell.isSelected ? Colours.palette.m3primary : Colours.palette.m3tertiary

                                scale: 0.6
                                Component.onCompleted: scale = 1

                                Behavior on scale {
                                    SequentialAnimation {
                                        PauseAnimation {
                                            duration: cell.index * 8
                                        }
                                        Anim {
                                            type: Anim.FastSpatial
                                        }
                                    }
                                }

                                Behavior on opacity {
                                    Anim {
                                        type: Anim.DefaultEffects
                                    }
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: (cell.modelData?.markers ?? 0) > 0 ? -2 : 0
                                    text: cell.modelData?.day ?? ""
                                    font: Tokens.font.label.small
                                    color: cell.lvl >= 3 ? Colours.palette.m3onPrimary : cell.lvl >= 1 ? Colours.palette.m3onSurface : Colours.palette.m3outline
                                }

                                StyledRect {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 3
                                    visible: (cell.modelData?.markers ?? 0) > 0
                                    implicitWidth: 4
                                    implicitHeight: 4
                                    radius: Tokens.rounding.full
                                    color: Colours.palette.m3tertiary
                                }

                                StateLayer {
                                    disabled: !cell.hasActivity || cell.isFuture
                                    radius: parent.radius
                                    onClicked: root.selectDay(cell.modelData.day)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.small

                Stat {
                    label: Tr.tr("Sessions")
                    value: root.sessionCount
                }

                Stat {
                    label: Tr.tr("Total")
                    value: root.totalMinutes > 0 ? root.service.formatPlaytime(root.totalMinutes) : "–"
                }

                Stat {
                    label: Tr.tr("Longest")
                    value: root.longestMinutes > 0 ? root.service.formatPlaytime(root.longestMinutes) : "–"
                }

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 3

                    StyledText {
                        anchors.verticalCenter: parent?.verticalCenter
                        rightPadding: 2
                        text: Tr.tr("Less")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }

                    Repeater {
                        model: root.levels + 1

                        StyledRect {
                            required property int index

                            anchors.verticalCenter: parent?.verticalCenter
                            implicitWidth: 10
                            implicitHeight: 10
                            radius: 3
                            color: root.levelColour(index)
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent?.verticalCenter
                        leftPadding: 2
                        text: Tr.tr("More")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !root.hasPlay
                    horizontalAlignment: Text.AlignHCenter
                    text: root.monthMarkers > 0 ? Tr.tr("Dots mark achievement days. Playtime is recorded from now on.") : Tr.tr("Playtime is recorded while the shell is running.")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outline
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    component Stat: StyledRect {
        id: stat

        property string label
        property var value

        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerHigh

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - Tokens.padding.small * 2
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: String(stat.value)
                font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: stat.label
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }
}
