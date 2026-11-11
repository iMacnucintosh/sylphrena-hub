pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Sylphrena.I18n
import "steam"

// Service of the Games extension: the Steam façade used by the games tab and the settings. Logic
// lives in steam/* (Format, Api, Library, Achievements, Local, Activity). It exists only while the
// extension is enabled. Settings (ext.config): apiKey, steamId, refreshMinutes.
Scope {
    id: root

    // Injected by the base (services/Extensions.qml)
    required property var ext

    // The service exists only while the extension is enabled (kept so the code below reads as before)
    readonly property bool enabled: true
    readonly property string apiKey: root.ext.config.get("apiKey", "")
    readonly property string steamIdInput: root.ext.config.get("steamId", "")
    readonly property int refreshMinutes: Math.max(1, root.ext.config.get("refreshMinutes", 10) || 10)
    readonly property bool configured: apiKey.length > 0 && steamIdInput.length > 0
    // Cap the achievements sampling GETs (1 per candidate game) — a big
    // library otherwise fires hundreds of requests on the first reload.
    readonly property int achievementSampleLimit: 60
    // The periodic reload only runs while the dashboard shows the Games tab
    // (fetched data is irrelevant while hidden).
    property bool gamesTabVisible: false

    property bool loading: false
    property string error: ""
    property string resolvedSteamId: ""
    property int steamLevel: 0
    property var profile: null
    property list<var> recentGames: []
    property list<var> nonSteamGames: [] // experimental: local shortcuts.vdf
    property list<string> hiddenAppIds: [] // Steam "Hidden" collection (local)
    property string focusAppId: ""
    // True while the featured game was chosen by us (not by a click): it may change when more data arrives
    property bool focusAuto: true
    property string focusGameName: ""
    property list<var> focusAchievements: [] // unlocked rarest first, then locked most common first
    readonly property list<int> focusUnlockTimes: focusAchievements.map(a => a.unlockTime).filter(t => t > 0)
    property var activity: ({}) // { days, sessions, active } from steam-activity.py
    property string lastActivityJson: ""
    property real activityNow: Date.now() / 1000
    readonly property var dailyPlaytime: activity.days ?? {}
    readonly property var focusSessions: {
        const list = (activity.sessions ?? {})[focusAppId] ?? [];
        const liveStart = (activity.active ?? {})[focusAppId];
        return liveStart ? [{
                start: liveStart,
                end: Math.max(liveStart, activityNow),
                live: true
            }, ...list] : list;
    }
    readonly property string activityScript: activityMod.activityScript
    property var focusProgress: null
    readonly property var focusGame: recentGames.find(g => g.appId === focusAppId) ?? topGamesByPlaytime.find(g => g.appId === focusAppId) ?? nonSteamGames.find(g => g.appId === focusAppId) ?? null
    readonly property bool focusPlayingNow: !!profile?.gameId && profile.gameId === focusAppId
    readonly property bool focusNonSteam: !!focusGame?.nonSteam
    readonly property string nonSteamScript: localMod.nonSteamScript
    property bool focusLoading: false
    property string focusError: ""
    // Generic library / social stats (header)
    property int gameCount: 0
    property int totalPlaytimeMinutes: 0
    property int recentPlaytimeMinutes: 0
    property list<var> ownedGames: [] // full owned list; derived stats skip hidden
    property list<var> topGamesByPlaytime: []
    property list<var> topGamesByRecency: [] // owned games with lastPlayed, newest first
    property list<string> achievementCandidates: [] // played games with community stats, by playtime

    function isHiddenApp(appId: string): bool {
        return libraryMod.isHiddenApp(appId);
    }

    function applyHiddenFilter(): void {
        libraryMod.applyHiddenFilter();
    }

    function refreshOwnedDerived(): void {
        libraryMod.refreshOwnedDerived();
    }

    // Cover picker: Steam + Non-Steam, sorted by last played (playing now first)
    readonly property var pickerGames: {
        const map = {};
        const bump = Math.floor(Date.now() / 1000) + 10;

        function put(game, fallbackLast) {
            if (!game?.appId || root.isHiddenApp(game.appId))
                return;
            const prev = map[game.appId] || {};
            // Real timestamps win; the fallback only orders games that have none (it used to be a
            // fake "just now" that always beat real, more recent plays)
            const lastPlayed = Math.max(prev.lastPlayed || 0, game.lastPlayed || 0) || fallbackLast || 0;
            map[game.appId] = Object.assign({}, prev, game, {
                lastPlayed: lastPlayed,
                headerUrl: game.headerUrl || prev.headerUrl || "",
                capsuleUrl: game.capsuleUrl || prev.capsuleUrl || ""
            });
        }

        for (const g of root.topGamesByRecency)
            put(g, 0);
        for (const g of root.topGamesByPlaytime)
            put(g, 0);
        // Recently played from Steam may lack rtime; keep their relative order near "now"
        for (let i = 0; i < root.recentGames.length; i++)
            put(root.recentGames[i], bump - 1 - i);
        for (const g of root.nonSteamGames)
            put(g, 0);

        // Real sessions (reaper) are the best evidence of when a game was last played
        const sess = root.activity?.sessions ?? {};
        for (const id of Object.keys(sess)) {
            if (!map[id])
                continue;
            const end = Math.max(0, ...(sess[id] ?? []).map(x => x.end || 0));
            if (end > (map[id].lastPlayed || 0))
                map[id] = Object.assign({}, map[id], {
                    lastPlayed: end
                });
        }

        if (root.profile?.gameId && map[root.profile.gameId])
            map[root.profile.gameId] = Object.assign({}, map[root.profile.gameId], {
                lastPlayed: bump + 1
            });

        return Object.values(map).sort((a, b) => (b.lastPlayed || 0) - (a.lastPlayed || 0));
    }
    property int friendsTotal: -1
    property int friendsOnline: -1
    property int friendsInGame: -1
    property string friendsError: ""
    property list<var> friendsPreview: [] // online friends with avatars
    property var libraryAchievements: null // { unlocked, total, percent, sampled, perfect }
    property bool libraryAchievementsLoading: false

    property int gen: 0
    property var schemaCache: ({})
    property var globalPctCache: ({})
    property var achievementsCache: ({})

    readonly property string statusText: {
        if (!enabled)
            return Tr.tr("Disabled — Games tab is hidden");
        if (!configured)
            return Tr.tr("Needs API key and Steam ID");
        if (loading)
            return Tr.tr("Loading Steam data…");
        if (error.length > 0)
            return error;
        if (profile?.personaName)
            return Tr.tr("Connected as %1").arg(profile.personaName);
        return Tr.tr("Ready");
    }

    readonly property string personaStateLabel: {
        // Touch profile so this binding tracks persona/game changes (function
        // bodies alone are not dependency-tracked by the QML engine).
        const _profile = root.profile;
        return formatMod.personaStateLabel();
    }

    function setApiKey(key: string): void {
        root.ext.config.set("apiKey", (key || "").trim());
    }

    function setSteamId(id: string): void {
        root.ext.config.set("steamId", (id || "").trim());
    }

    function setRefreshMinutes(mins: int): void {
        root.ext.config.set("refreshMinutes", Math.max(1, Math.min(180, Math.round(mins || 10))));
    }

    function steamLang(): string {
        return formatMod.steamLang();
    }

    function capsuleUrl(appId: string): string {
        return formatMod.capsuleUrl(appId);
    }

    function headerUrl(appId: string): string {
        return formatMod.headerUrl(appId);
    }

    function artCandidates(appId: string, preferred: string): var {
        return formatMod.artCandidates(appId, preferred);
    }

    function loadNonSteam(): void {
        localMod.loadNonSteam();
    }

    function formatPlaytime(minutes: int): string {
        return formatMod.formatPlaytime(minutes);
    }

    function extractSteamIdOrVanity(raw: string): var {
        return formatMod.extractSteamIdOrVanity(raw);
    }

    function apiUrl(iface: string, method: string, version: string, params: var): string {
        return apiMod.apiUrl(iface, method, version, params);
    }

    function getJson(url: string, ok: var, fail: var): void {
        apiMod.getJson(url, ok, fail);
    }

    function logPlaytime(games: var): void {
        activityMod.logPlaytime(games);
    }

    function applyActivity(text: string): void {
        activityMod.applyActivity(text);
    }

    // The non-Steam library arrives after the Steam one: if the featured game was picked automatically,
    // pick again now that every game is known (otherwise a non-Steam game played last would lose to a
    // Steam one that was merely the first to load)
    function repickAutoFocus(): void {
        if (!root.focusAuto || root.profile?.gameId)
            return;
        const best = root.pickerGames[0];
        if (!best?.appId || String(best.appId) === root.focusAppId)
            return;
        root.focusAppId = String(best.appId);
        root.focusGameName = best.name || "";
        achievementsMod.loadFocusAchievements(root.gen);
    }

    function setFocusApp(appId: string, name: string): void {
        if (!appId || String(appId) === root.focusAppId)
            return;
        root.focusAuto = false;
        root.focusAppId = String(appId);
        root.focusGameName = name || "";
        achievementsMod.loadFocusAchievements(root.gen);
    }

    function clearData(): void {
        root.resolvedSteamId = "";
        root.steamLevel = 0;
        root.profile = null;
        root.recentGames = [];
        root.nonSteamGames = [];
        root.hiddenAppIds = [];
        root.focusAppId = "";
        root.focusAuto = true;
        root.focusGameName = "";
        root.focusAchievements = [];
        root.focusProgress = null;
        root.focusLoading = false;
        root.focusError = "";
        root.gameCount = 0;
        root.totalPlaytimeMinutes = 0;
        root.recentPlaytimeMinutes = 0;
        root.ownedGames = [];
        root.topGamesByPlaytime = [];
        root.topGamesByRecency = [];
        root.achievementCandidates = [];
        root.friendsTotal = -1;
        root.friendsOnline = -1;
        root.friendsInGame = -1;
        root.friendsError = "";
        root.friendsPreview = [];
        root.activity = ({});
        root.lastActivityJson = "";
        root.libraryAchievements = null;
        root.libraryAchievementsLoading = false;
        root.error = "";
        root.loading = false;
    }

    function reload(): void {
        if (!root.enabled || !root.configured) {
            root.clearData();
            if (root.enabled && !root.configured)
                root.error = Tr.tr("Needs API key and Steam ID");
            return;
        }

        const g = ++root.gen;
        root.loading = true;
        root.error = "";

        const parsed = root.extractSteamIdOrVanity(root.steamIdInput);
        if (parsed.kind === "empty") {
            root.loading = false;
            root.error = Tr.tr("Needs API key and Steam ID");
            return;
        }

        if (parsed.kind === "id") {
            root.resolvedSteamId = parsed.value;
            libraryMod.fetchCore(g);
            return;
        }

        apiMod.resolveVanity(parsed.value, g, sid => {
            root.resolvedSteamId = sid;
            libraryMod.fetchCore(g);
        }, err => {
            root.loading = false;
            root.error = err;
        });
    }

    function fetchCore(g: int): void {
        libraryMod.fetchCore(g);
    }

    function fetchFriends(g: int, done: var): void {
        libraryMod.fetchFriends(g, done);
    }

    function sampleLibraryAchievements(g: int): void {
        achievementsMod.sampleLibraryAchievements(g);
    }

    function pickInitialFocus(g: int): void {
        achievementsMod.pickInitialFocus(g);
    }

    function loadFocusAchievements(g: int): void {
        achievementsMod.loadFocusAchievements(g);
    }

    function buildAchievementViews(appId: string, list: var, schemaMap: var, globalMap: var): void {
        achievementsMod.buildAchievementViews(appId, list, schemaMap, globalMap);
    }

    function maybeReloadOnConfig(): void {
        if (root.enabled && root.configured)
            root.reload();
        else
            root.clearData();
    }

    SteamFormat {
        id: formatMod
        host: root
    }

    SteamApi {
        id: apiMod
        host: root
    }

    SteamActivity {
        id: activityMod
        host: root
    }

    SteamLocal {
        id: localMod
        host: root
    }

    SteamAchievements {
        id: achievementsMod
        host: root
        api: apiMod
    }

    SteamLibrary {
        id: libraryMod
        host: root
        api: apiMod
        achievements: achievementsMod
        local: localMod
        activity: activityMod
    }

    // React to the settings changing (the extension's own config, not the shell's)
    onApiKeyChanged: {
        achievementsMod.clearCaches(true);
        root.maybeReloadOnConfig();
    }
    onSteamIdInputChanged: {
        achievementsMod.clearCaches(true);
        root.maybeReloadOnConfig();
    }

    Timer {
        interval: root.refreshMinutes * 60 * 1000
        running: root.enabled && root.configured && root.gamesTabVisible
        repeat: true
        onTriggered: root.reload()
    }

    Component.onCompleted: {
        // Defer full library/API reload until Games tab asks; still start activity poll
        activityMod.startPollIfNeeded();
    }
}
