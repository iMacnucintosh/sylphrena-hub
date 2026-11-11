import QtQuick
import QtQuick.Layouts
import Sylphrena.I18n
import qs.modules.nexus.common

// Settings of the Hydration extension, shown inside its card in Nexus (Panels → Dashboard).
ColumnLayout {
    id: root

    // Injected by the base
    required property var ext
    required property var service

    spacing: 0

    SpinSettingRow {
        label: Tr.tr("Daily goal")
        subtext: Tr.tr("Target water intake per day (ml)")
        value: root.service.dailyGoalMl
        from: 500
        to: 8000
        stepSize: 100
        onMoved: v => root.service.setDailyGoal(v)
    }

    SpinSettingRow {
        label: Tr.tr("Reminder interval")
        subtext: Tr.tr("Minutes without a sip before a reminder")
        value: root.service.reminderMinutes
        from: 5
        to: 120
        stepSize: 5
        onMoved: v => root.service.setReminderMinutes(v)
    }

    SpinSettingRow {
        label: Tr.tr("Preset %1").arg(1)
        subtext: Tr.tr("Quick-add button amount (ml)")
        value: root.service.presets[0]
        from: 1
        to: 1000
        stepSize: 1
        onMoved: v => root.service.setPreset(0, v)
    }

    SpinSettingRow {
        label: Tr.tr("Preset %1").arg(2)
        value: root.service.presets[1]
        from: 1
        to: 1000
        stepSize: 1
        onMoved: v => root.service.setPreset(1, v)
    }

    SpinSettingRow {
        label: Tr.tr("Preset %1").arg(3)
        value: root.service.presets[2]
        from: 1
        to: 1000
        stepSize: 1
        onMoved: v => root.service.setPreset(2, v)
    }

    SpinSettingRow {
        label: Tr.tr("Preset %1").arg(4)
        value: root.service.presets[3]
        from: 1
        to: 1000
        stepSize: 1
        onMoved: v => root.service.setPreset(3, v)
    }
}
