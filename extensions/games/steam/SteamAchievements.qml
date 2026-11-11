pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Sylphrena.I18n
import qs.utils

// Player achievements + schema + global % (RAM + disk TTL ~1 day).
QtObject {
    id: root

    required property var host
    required property var api

    readonly property int cacheTtlSec: 86400
    readonly property int cacheVersion: 1
    readonly property string cachePath: `${Paths.state}/steam-achievements-cache.json`

    property var _diskPayload: null
    property bool _diskLoaded: false

    function schedulePersist(): void {
        persistTimer.restart();
    }

    function clearCaches(wipeDisk: bool): void {
        root.host.achievementsCache = ({});
        root.host.schemaCache = ({});
        root.host.globalPctCache = ({});
        root._diskPayload = null;
        if (wipeDisk)
            Qt.callLater(() => cacheFile.setText(""));
    }

    function invalidatePlayerAchievements(appId: string): void {
        if (!appId)
            return;
        const cache = Object.assign({}, root.host.achievementsCache);
        delete cache[appId];
        root.host.achievementsCache = cache;
        if (root._diskPayload?.achievements) {
            const diskAch = Object.assign({}, root._diskPayload.achievements);
            delete diskAch[appId];
            root._diskPayload = Object.assign({}, root._diskPayload, {
                achievements: diskAch
            });
        }
        root.schedulePersist();
    }

    function applyDiskCache(): void {
        const data = root._diskPayload;
        if (!data || data.version !== root.cacheVersion)
            return;
        const age = (Date.now() / 1000) - (Number(data.savedAt) || 0);
        if (age > root.cacheTtlSec) {
            root._diskPayload = null;
            return;
        }

        // Schema / global % are not account-specific; safe to warm early.
        if (data.schema && typeof data.schema === "object")
            root.host.schemaCache = data.schema;
        if (data.globalPct && typeof data.globalPct === "object")
            root.host.globalPctCache = data.globalPct;

        // Player achievements only when steamId matches (or not yet resolved).
        if (data.achievements && typeof data.achievements === "object") {
            if (!root.host.resolvedSteamId || !data.steamId || data.steamId === root.host.resolvedSteamId)
                root.host.achievementsCache = data.achievements;
        }
    }

    function onResolvedSteamId(sid: string): void {
        const data = root._diskPayload;
        if (!data || !sid)
            return;
        if (data.steamId && data.steamId !== sid) {
            // Wrong account on disk — drop player achievements, keep schema/global.
            root.host.achievementsCache = ({});
            return;
        }
        if (data.achievements && typeof data.achievements === "object")
            root.host.achievementsCache = data.achievements;
    }

    function persist(): void {
        if (!root._diskLoaded)
            return;
        const sid = root.host.resolvedSteamId || "";
        const payload = {
            version: root.cacheVersion,
            steamId: sid,
            savedAt: Math.floor(Date.now() / 1000),
            achievements: root.host.achievementsCache || {},
            schema: root.host.schemaCache || {},
            globalPct: root.host.globalPctCache || {}
        };
        root._diskPayload = payload;
        try {
            cacheFile.setText(JSON.stringify(payload));
        } catch (e) {
            console.warn(`Steam achievements cache write failed: ${e}`);
        }
    }

    function rememberAchievements(appId: string, list: var): void {
        root.host.achievementsCache[appId] = list;
        root.schedulePersist();
    }

    function rememberSchema(key: string, map: var): void {
        root.host.schemaCache[key] = map;
        root.schedulePersist();
    }

    function rememberGlobal(appId: string, map: var): void {
        root.host.globalPctCache[appId] = map;
        root.schedulePersist();
    }

    // Steam's "average completion" only counts games with at least one unlock
    function sampleLibraryAchievements(g: int): void {
        // Candidates are sorted by playtime so the cap keeps the most played;
        // the tail is unmeasured by design.
        const sample = root.host.achievementCandidates.slice(0, root.host.achievementSampleLimit);
        if (sample.length === 0) {
            root.host.libraryAchievements = null;
            root.host.libraryAchievementsLoading = false;
            return;
        }

        root.host.libraryAchievementsLoading = true;
        const workers = Math.min(4, sample.length);
        let idx = 0;
        let active = workers;
        let processed = 0;
        let unlocked = 0;
        let total = 0;
        let perfect = 0;
        let started = 0;
        let completionSum = 0;
        let dirty = false;

        function publish(): void {
            root.host.libraryAchievements = {
                unlocked: unlocked,
                total: total,
                percent: started > 0 ? completionSum / started : 0,
                sampled: started,
                perfect: perfect
            };
        }

        function next(): void {
            if (g !== root.host.gen)
                return;
            if (idx >= sample.length) {
                if (--active === 0) {
                    root.host.libraryAchievementsLoading = false;
                    publish();
                    if (dirty)
                        root.schedulePersist();
                }
                return;
            }
            const appId = sample[idx++];
            const cached = root.host.achievementsCache[appId];
            if (cached) {
                applyList(cached);
                next();
                return;
            }
            root.api.getJson(root.api.apiUrl("ISteamUserStats", "GetPlayerAchievements", "v1", {
                key: root.host.apiKey,
                steamid: root.host.resolvedSteamId,
                appid: appId
            }), json => {
                if (g !== root.host.gen)
                    return;
                const list = json?.playerstats?.success === false ? null : json?.playerstats?.achievements;
                if (list) {
                    root.host.achievementsCache[appId] = list;
                    dirty = true;
                    applyList(list);
                }
                next();
            }, () => next());
        }

        function applyList(list: var): void {
            processed++;
            if (list && list.length > 0) {
                let u = 0;
                for (let i = 0; i < list.length; i++) {
                    if (list[i].achieved === 1 || list[i].achieved === true)
                        u++;
                }
                unlocked += u;
                total += list.length;
                if (u > 0) {
                    started++;
                    completionSum += u / list.length;
                }
                if (u === list.length)
                    perfect++;
            }
            if (processed % 8 === 0)
                publish();
        }

        for (let w = 0; w < workers; w++)
            next();
    }

    function pickInitialFocus(g: int): void {
        if (g !== root.host.gen)
            return;

        if (root.host.focusAppId) {
            const still = root.host.pickerGames.find(game => game.appId === root.host.focusAppId);
            if (still) {
                root.host.focusGameName = still.name || root.host.focusGameName;
                if (!still.nonSteam)
                    root.invalidatePlayerAchievements(still.appId);
                root.loadFocusAchievements(g);
                return;
            }
        }

        let appId = "";
        let name = "";
        if (root.host.profile?.gameId) {
            appId = root.host.profile.gameId;
            name = root.host.profile.gameExtraInfo || "";
        } else if (root.host.recentGames.length > 0) {
            appId = root.host.recentGames[0].appId;
            name = root.host.recentGames[0].name;
        }

        root.host.focusAppId = appId;
        root.host.focusGameName = name;
        if (appId)
            root.loadFocusAchievements(g);
        else {
            root.host.loading = false;
            root.host.focusAchievements = [];
            root.host.focusProgress = null;
        }
    }

    function loadFocusAchievements(g: int): void {
        const appId = root.host.focusAppId;
        if (!appId || !root.host.resolvedSteamId) {
            root.host.loading = false;
            return;
        }

        const localGame = root.host.nonSteamGames.find(g => g.appId === appId);
        if (localGame) {
            root.host.loading = false;
            root.host.focusLoading = false;
            root.host.focusError = localGame.tracked ? Tr.tr("Playtime tracked by Millennium") : Tr.tr("Non-Steam game — no Steam achievements");
            root.host.focusAchievements = [];
            root.host.focusProgress = null;
            return;
        }

        root.host.focusLoading = true;
        let pending = 3;
        let playerAchievements = null;
        let schemaMap = null;
        let globalMap = null;
        let privateProfile = false;
        const lang = root.host.steamLang();

        function finish(): void {
            pending--;
            if (pending > 0)
                return;
            if (g !== root.host.gen || appId !== root.host.focusAppId)
                return;

            root.host.loading = false;
            root.host.focusLoading = false;
            if (privateProfile || !playerAchievements) {
                root.host.focusError = privateProfile ? Tr.tr("Steam achievements are private for this profile") : Tr.tr("This game has no achievements");
                root.host.focusAchievements = [];
                root.host.focusProgress = null;
                return;
            }

            root.host.focusError = "";
            root.buildAchievementViews(appId, playerAchievements, schemaMap || {}, globalMap || {});
        }

        const cachedAch = root.host.achievementsCache[appId];
        if (cachedAch) {
            playerAchievements = cachedAch;
            finish();
        } else {
            root.api.getJson(root.api.apiUrl("ISteamUserStats", "GetPlayerAchievements", "v1", {
                key: root.host.apiKey,
                steamid: root.host.resolvedSteamId,
                appid: appId,
                l: lang
            }), json => {
                if (g !== root.host.gen)
                    return;
                if (json?.playerstats?.success === false || json?.playerstats?.error) {
                    privateProfile = /private|not public/i.test(json?.playerstats?.error || "");
                    finish();
                    return;
                }
                const list = json?.playerstats?.achievements;
                if (!list) {
                    finish();
                    return;
                }
                if (!root.host.focusGameName && json.playerstats.gameName)
                    root.host.focusGameName = json.playerstats.gameName;
                playerAchievements = list;
                root.rememberAchievements(appId, list);
                finish();
            }, () => {
                if (g !== root.host.gen)
                    return;
                finish();
            });
        }

        const schemaKey = `${appId}:${lang}`;
        const cachedSchema = root.host.schemaCache[schemaKey];
        if (cachedSchema) {
            schemaMap = cachedSchema;
            finish();
        } else {
            root.api.getJson(root.api.apiUrl("ISteamUserStats", "GetSchemaForGame", "v2", {
                key: root.host.apiKey,
                appid: appId,
                l: lang
            }), json => {
                if (g !== root.host.gen)
                    return;
                const achs = json?.game?.availableGameStats?.achievements || [];
                const map = {};
                for (let i = 0; i < achs.length; i++) {
                    const a = achs[i];
                    map[a.name] = {
                        displayName: a.displayName || a.name,
                        description: a.description || "",
                        icon: a.icon || "",
                        icongray: a.icongray || ""
                    };
                }
                schemaMap = map;
                root.rememberSchema(schemaKey, map);
                finish();
            }, () => {
                if (g !== root.host.gen)
                    return;
                schemaMap = {};
                finish();
            });
        }

        const cachedGlobal = root.host.globalPctCache[appId];
        if (cachedGlobal) {
            globalMap = cachedGlobal;
            finish();
        } else {
            root.api.getJson(root.api.apiUrl("ISteamUserStats", "GetGlobalAchievementPercentagesForApp", "v2", {
                gameid: appId
            }), json => {
                if (g !== root.host.gen)
                    return;
                const list = json?.achievementpercentages?.achievements || [];
                const map = {};
                for (let i = 0; i < list.length; i++)
                    map[list[i].name] = Number(list[i].percent) || 0;
                globalMap = map;
                root.rememberGlobal(appId, map);
                finish();
            }, () => {
                if (g !== root.host.gen)
                    return;
                globalMap = {};
                finish();
            });
        }
    }

    function buildAchievementViews(appId: string, list: var, schemaMap: var, globalMap: var): void {
        const gameName = root.host.focusGameName || (root.host.recentGames.find(g => g.appId === appId)?.name) || Tr.tr("Unknown game");
        const enriched = [];
        let unlocked = 0;

        for (let i = 0; i < list.length; i++) {
            const a = list[i];
            const meta = schemaMap[a.apiname] || {};
            const achieved = a.achieved === 1 || a.achieved === true;
            if (achieved)
                unlocked++;
            enriched.push({
                apiName: a.apiname,
                name: meta.displayName || a.name || a.apiname,
                description: meta.description || "",
                icon: achieved ? (meta.icon || "") : (meta.icongray || meta.icon || ""),
                unlocked: achieved,
                unlockTime: a.unlocktime || 0,
                globalPercent: globalMap[a.apiname] ?? -1,
                gameName: gameName,
                appId: appId
            });
        }

        const total = enriched.length;
        root.host.focusProgress = {
            unlocked: unlocked,
            total: total,
            percent: total > 0 ? unlocked / total : 0,
            gameName: gameName,
            appId: appId
        };

        const pctOf = a => a.globalPercent >= 0 ? a.globalPercent : -1;
        const unlockedList = enriched.filter(a => a.unlocked);
        unlockedList.sort((a, b) => (pctOf(a) < 0 ? 101 : pctOf(a)) - (pctOf(b) < 0 ? 101 : pctOf(b)));
        const lockedList = enriched.filter(a => !a.unlocked);
        lockedList.sort((a, b) => pctOf(b) - pctOf(a));
        root.host.focusAchievements = unlockedList.concat(lockedList);
    }

    readonly property Timer persistTimer: Timer {
        interval: 400
        onTriggered: root.persist()
    }

    readonly property FileView cacheFile: FileView {
        printErrors: false
        path: root.cachePath
        onLoaded: {
            root._diskLoaded = true;
            try {
                const raw = text() || "";
                if (!raw.trim()) {
                    root._diskPayload = null;
                    return;
                }
                const data = JSON.parse(raw);
                if (!data || data.version !== root.cacheVersion) {
                    root._diskPayload = null;
                    return;
                }
                root._diskPayload = data;
                root.applyDiskCache();
            } catch (e) {
                console.warn(`Unable to parse steam-achievements-cache.json: ${e}`);
                root._diskPayload = null;
            }
        }
        onLoadFailed: err => {
            root._diskLoaded = true;
            root._diskPayload = null;
            if (err !== FileViewError.FileNotFound)
                console.warn(`Unable to load steam-achievements-cache.json: ${err}`);
        }
    }
}
