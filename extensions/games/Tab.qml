pragma ComponentBehavior: Bound

import "games"
import QtQuick
import QtQuick.Layouts
import M3Shapes
import Sylphrena.Config
import Sylphrena.I18n
import qs.components
import qs.components.controls
import qs.components.images
import qs.services

Item {
    id: root

    // Injected by the base: the extension, its service, and the screen state
    required property var ext
    required property var service
    property var screenState

    readonly property bool hasProfile: !!root.service.profile
    readonly property real achPercent: root.service.libraryAchievements?.percent ?? 0
    property bool steamShowsSessions
    property string lastFocusAppId

    implicitWidth: 840
    implicitHeight: layout.implicitHeight

    Component.onCompleted: {
        root.service.gamesTabVisible = Qt.binding(() => root.visible && root.service.enabled);
        if (root.service.enabled && root.service.configured && !root.service.profile && !root.service.loading)
            root.service.reload();
    }

    // Leave no stale "visible" flag behind us when the loader deactivates.
    Component.onDestruction: root.service.gamesTabVisible = false

    Connections {
        target: root.service
        function onFocusAppIdChanged(): void {
            if (root.lastFocusAppId && root.lastFocusAppId !== root.service.focusAppId)
                root.steamShowsSessions = false;
            root.lastFocusAppId = root.service.focusAppId;
        }
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.medium

        Loader {
            Layout.fillWidth: true
            active: !root.service.configured || (root.service.error.length > 0 && !root.hasProfile)
            visible: active
            sourceComponent: PlaceholderCard {
                icon: !root.service.configured ? "key" : "error"
                title: !root.service.configured ? Tr.tr("Configure Steam") : Tr.tr("Could not load Steam data")
                body: !root.service.configured ? Tr.tr("Add your API key and Steam ID in Nexus → Extensions.") : root.service.error
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.preferredHeight: 320
            active: root.service.configured && !root.hasProfile && root.service.error.length === 0
            visible: active
            sourceComponent: Item {
                LoadingIndicator {
                    anchors.centerIn: parent
                }
            }
        }

        ProfileHeader {

            service: root.service
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.small
            visible: root.hasProfile
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.hasProfile
            spacing: Tokens.spacing.medium

            StatCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                revealDelay: 0
                icon: "sports_esports"
                label: Tr.tr("Games")
                caption: Tr.tr("in your library")
                value: root.service.gameCount > 0 ? root.service.gameCount : -1
                shape: MaterialShape.Cookie9Sided
                accent: Colours.palette.m3primary
                shapeColour: Colours.palette.m3primaryContainer
                onShapeColour: Colours.palette.m3onPrimaryContainer

                RowLayout {
                    anchors.fill: parent
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: root.service.topGamesByPlaytime.slice(0, 4)

                        ClipRect {
                            id: capsule

                            required property var modelData

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surfaceContainerHighest

                            FadeImage {
                                anchors.fill: parent
                                source: capsule.modelData.capsuleUrl
                            }
                        }
                    }
                }
            }

            StatCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                revealDelay: 60
                icon: "schedule"
                label: Tr.tr("Hours")
                caption: root.service.recentPlaytimeMinutes > 0 ? Tr.tr("+%1 in 2 weeks").arg(root.service.formatPlaytime(root.service.recentPlaytimeMinutes)) : Tr.tr("played in total")
                value: root.service.totalPlaytimeMinutes > 0 ? root.service.totalPlaytimeMinutes / 60 : -1
                formatter: v => String(Math.round(v)).replace(/\B(?=(\d{3})+(?!\d))/g, Tr.locale.groupSeparator)
                shape: MaterialShape.Clover4Leaf
                accent: Colours.palette.m3secondary
                shapeColour: Colours.palette.m3secondaryContainer
                onShapeColour: Colours.palette.m3onSecondaryContainer

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Tokens.spacing.extraSmall

                    PlaytimeShareBar {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.service.topGamesByPlaytime.length > 0 ? Tr.tr("Top: %1").arg(root.service.topGamesByPlaytime[0].name) : ""
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            StatCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                revealDelay: 120
                icon: "emoji_events"
                label: Tr.tr("Achievements")
                caption: root.service.libraryAchievements ? Tr.tr("%1 / %2 unlocked").arg(root.service.libraryAchievements.unlocked).arg(root.service.libraryAchievements.total) : (root.service.libraryAchievementsLoading ? Tr.tr("Loading…") : "")
                value: root.service.libraryAchievements ? root.achPercent * 100 : -1
                formatter: v => `${Math.round(v)}%`
                shape: {
                    if (root.achPercent >= 0.66)
                        return MaterialShape.SoftBurst;
                    if (root.achPercent >= 0.33)
                        return MaterialShape.Sunny;
                    return MaterialShape.Cookie4Sided;
                }
                accent: Colours.palette.m3tertiary
                shapeColour: Colours.palette.m3tertiaryContainer
                onShapeColour: Colours.palette.m3onTertiaryContainer

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Tokens.spacing.extraSmall

                    StyledProgressBar {
                        Layout.fillWidth: true
                        implicitHeight: Tokens.padding.small
                        value: root.achPercent
                        fgColour: Colours.palette.m3tertiary
                        bgColour: Colours.palette.m3tertiaryContainer
                        indeterminate: root.service.libraryAchievementsLoading && !root.service.libraryAchievements
                    }

                    RowLayout {
                        spacing: 2

                        MaterialIcon {
                            text: "workspace_premium"
                            fill: 1
                            color: Colours.palette.m3tertiary
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: Tr.tr("%1 perfect games").arg(root.service.libraryAchievements?.perfect ?? 0)
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }

            StatCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                revealDelay: 180
                icon: "group"
                label: Tr.tr("Friends")
                caption: root.service.friendsOnline >= 0 ? Tr.tr("online · %1 in game").arg(Math.max(0, root.service.friendsInGame)) : Tr.tr("Private")
                value: root.service.friendsOnline
                shape: MaterialShape.Pentagon
                accent: Colours.palette.m3primary
                shapeColour: Colours.palette.m3primaryContainer
                onShapeColour: Colours.palette.m3onPrimaryContainer

                FriendAvatars {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        FocusHero {

            service: root.service
            Layout.fillWidth: true
            visible: root.hasProfile
        }

        RecentGamesRow {

            service: root.service
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall
            visible: root.hasProfile && root.service.pickerGames.length > 1
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.hasProfile
            spacing: Tokens.spacing.medium

            SessionList {

                service: root.service
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                visible: root.service.focusNonSteam || root.steamShowsSessions
                sessions: root.service.focusNonSteam ? (root.service.focusGame?.sessions ?? []) : root.service.focusSessions
                tracked: !root.service.focusNonSteam || !!root.service.focusGame?.tracked
                switchIcon: root.service.focusNonSteam ? "" : "trophy"
                onSwitchRequested: root.steamShowsSessions = false
            }

            AchievementList {

                service: root.service
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                visible: !root.service.focusNonSteam && !root.steamShowsSessions
                emptyText: root.service.focusLoading ? Tr.tr("Loading…") : root.service.focusError || Tr.tr("No achievements unlocked yet")
                model: root.service.focusAchievements
                switchIcon: "history"
                onSwitchRequested: root.steamShowsSessions = true
            }

            ActivityCard {

                service: root.service
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                gameKey: root.service.focusAppId
                sessions: root.service.focusNonSteam ? (root.service.focusGame?.sessions ?? []) : root.service.focusSessions
                dailyMinutes: root.service.focusNonSteam ? ({}) : (root.service.dailyPlaytime[root.service.focusAppId] ?? {})
                markerTimes: root.service.focusNonSteam ? [] : root.service.focusUnlockTimes
            }
        }
    }

    component PlaytimeShareBar: Item {
        id: bar

        readonly property var games: root.service.topGamesByPlaytime.slice(0, 4)
        readonly property real total: Math.max(1, root.service.totalPlaytimeMinutes)
        readonly property real topSum: games.reduce((acc, g) => acc + g.playtimeForever, 0)
        readonly property real gap: 3
        readonly property real usable: Math.max(0, width - gap * games.length)

        implicitHeight: Tokens.padding.small
        clip: true

        Row {
            anchors.fill: parent
            spacing: bar.gap

            Repeater {
                model: bar.games

                StyledRect {
                    required property var modelData
                    required property int index

                    implicitHeight: bar.height
                    implicitWidth: Math.max(bar.height, bar.usable * modelData.playtimeForever / bar.total)
                    radius: Tokens.rounding.full
                    color: Qt.alpha(Colours.palette.m3secondary, 1 - index * 0.2)

                    Behavior on implicitWidth {
                        Anim {
                            type: Anim.StandardLarge
                        }
                    }
                }
            }

            StyledRect {
                implicitHeight: bar.height
                visible: implicitWidth > bar.height
                implicitWidth: bar.usable * (bar.total - bar.topSum) / bar.total
                radius: Tokens.rounding.full
                color: Colours.palette.m3secondaryContainer
            }
        }
    }

    component FriendAvatars: Row {
        spacing: -8

        Repeater {
            model: root.service.friendsPreview.slice(0, 6)

            StyledRect {
                id: avatar

                required property var modelData

                implicitWidth: 30
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: modelData.inGame ? Colours.palette.m3tertiary : Colours.palette.m3surfaceContainer

                ClipRect {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerHighest

                    FadeImage {
                        anchors.fill: parent
                        source: avatar.modelData.avatarUrl
                    }
                }
            }
        }

        StyledRect {
            visible: root.service.friendsOnline > 6
            implicitWidth: 30
            implicitHeight: 30
            radius: Tokens.rounding.full
            color: Colours.palette.m3primaryContainer

            StyledText {
                anchors.centerIn: parent
                text: `+${root.service.friendsOnline - 6}`
                font: Tokens.font.label.builders.small.weight(Font.DemiBold).build()
                color: Colours.palette.m3onPrimaryContainer
            }
        }

        MaterialIcon {
            visible: root.service.friendsOnline < 0
            text: "lock"
            color: Colours.palette.m3outline
            fontStyle: Tokens.font.icon.medium
        }
    }
}
