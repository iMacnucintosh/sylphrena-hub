pragma ComponentBehavior: Bound

import QtQuick
import Sylphrena.I18n

// Profile / level / recent / owned / friends fetch + owned derived stats.
QtObject {
    id: root

    required property var host
    required property var api
    required property var achievements
    required property var local
    required property var activity

    function isHiddenApp(appId: string): bool {
        return root.host.hiddenAppIds.indexOf(String(appId)) >= 0;
    }

    function applyHiddenFilter(): void {
        root.host.recentGames = root.host.recentGames.filter(g => !root.isHiddenApp(g.appId));
        root.host.recentPlaytimeMinutes = root.host.recentGames.reduce((a, g) => a + (g.playtime2Weeks || 0), 0);
        root.refreshOwnedDerived();
        if (root.isHiddenApp(root.host.focusAppId)) {
            const next = root.host.pickerGames[0];
            if (next)
                root.host.setFocusApp(next.appId, next.name);
        }
    }

    function refreshOwnedDerived(): void {
        const visible = root.host.ownedGames.filter(g => !root.isHiddenApp(g.appId));
        root.host.gameCount = visible.length;
        root.host.totalPlaytimeMinutes = visible.reduce((a, g) => a + (g.playtimeForever || 0), 0);
        const byTime = visible.slice().sort((a, b) => b.playtimeForever - a.playtimeForever);
        root.host.topGamesByPlaytime = byTime.slice(0, 5);
        root.host.topGamesByRecency = visible.filter(g => g.lastPlayed > 0).sort((a, b) => b.lastPlayed - a.lastPlayed).slice(0, 20);
        root.host.achievementCandidates = visible.filter(g => g.hasStats && g.playtimeForever > 0).sort((a, b) => b.playtimeForever - a.playtimeForever).map(g => g.appId);
    }

    function fetchCore(g: int): void {
        const sid = root.host.resolvedSteamId;
        const key = root.host.apiKey;
        root.achievements.onResolvedSteamId(sid);
        let pending = 5;
        let failed = false;

        function done(): void {
            pending--;
            if (pending > 0)
                return;
            if (g !== root.host.gen)
                return;
            if (!failed) {
                root.local.loadNonSteam();
                root.achievements.pickInitialFocus(g);
                root.achievements.sampleLibraryAchievements(g);
            } else {
                root.host.loading = false;
            }
        }

        function fail(msg: string): void {
            if (g !== root.host.gen)
                return;
            failed = true;
            root.host.error = msg;
            done();
        }

        root.api.getJson(root.api.apiUrl("ISteamUser", "GetPlayerSummaries", "v2", {
            key: key,
            steamids: sid
        }), json => {
            if (g !== root.host.gen)
                return;
            const player = json?.response?.players?.[0];
            if (!player) {
                fail(Tr.tr("Steam profile not found"));
                return;
            }
            root.host.profile = {
                steamId: String(player.steamid || sid),
                personaName: player.personaname || "",
                avatarUrl: player.avatarfull || player.avatarmedium || player.avatar || "",
                profileUrl: player.profileurl || "",
                personaState: player.personastate ?? 0,
                gameExtraInfo: player.gameextrainfo || "",
                gameId: player.gameid ? String(player.gameid) : ""
            };
            done();
        }, fail);

        root.api.getJson(root.api.apiUrl("IPlayerService", "GetSteamLevel", "v1", {
            key: key,
            steamid: sid
        }), json => {
            if (g !== root.host.gen)
                return;
            root.host.steamLevel = json?.response?.player_level ?? 0;
            done();
        }, () => {
            if (g !== root.host.gen)
                return;
            root.host.steamLevel = 0;
            done();
        });

        root.api.getJson(root.api.apiUrl("IPlayerService", "GetRecentlyPlayedGames", "v1", {
            key: key,
            steamid: sid,
            count: 8
        }), json => {
            if (g !== root.host.gen)
                return;
            const games = json?.response?.games || [];
            let recentMins = 0;
            root.host.recentGames = games.map(game => {
                recentMins += game.playtime_2weeks || 0;
                return {
                    appId: String(game.appid),
                    name: game.name || Tr.tr("Unknown game"),
                    playtimeForever: game.playtime_forever || 0,
                    playtime2Weeks: game.playtime_2weeks || 0,
                    imgIconUrl: game.img_icon_url || "",
                    capsuleUrl: root.host.capsuleUrl(String(game.appid))
                };
            });
            root.host.recentPlaytimeMinutes = recentMins;
            done();
        }, fail);

        root.api.getJson(root.api.apiUrl("IPlayerService", "GetOwnedGames", "v1", {
            key: key,
            steamid: sid,
            include_appinfo: 1,
            include_played_free_games: 1
        }), json => {
            if (g !== root.host.gen)
                return;
            const resp = json?.response || {};
            const games = resp.games || [];
            const ranked = games.map(game => ({
                    appId: String(game.appid),
                    name: game.name || Tr.tr("Unknown game"),
                    playtimeForever: game.playtime_forever || 0,
                    lastPlayed: game.rtime_last_played || 0,
                    hasStats: !!game.has_community_visible_stats,
                    capsuleUrl: root.host.capsuleUrl(String(game.appid))
                }));
            root.host.ownedGames = ranked;
            root.refreshOwnedDerived();
            root.activity.logPlaytime(ranked);
            done();
        }, () => {
            if (g !== root.host.gen)
                return;
            root.host.ownedGames = [];
            root.refreshOwnedDerived();
            done();
        });

        root.fetchFriends(g, done);
    }

    function fetchFriends(g: int, done: var): void {
        root.api.getJson(root.api.apiUrl("ISteamUser", "GetFriendList", "v1", {
            key: root.host.apiKey,
            steamid: root.host.resolvedSteamId,
            relationship: "friend"
        }), json => {
            if (g !== root.host.gen)
                return;
            const friends = json?.friendslist?.friends || [];
            root.host.friendsTotal = friends.length;
            root.host.friendsError = "";
            if (friends.length === 0) {
                root.host.friendsOnline = 0;
                root.host.friendsInGame = 0;
                root.host.friendsPreview = [];
                done();
                return;
            }

            const ids = friends.map(f => String(f.steamid));
            const chunk = ids.slice(0, 100); // Steam summaries cap
            root.api.getJson(root.api.apiUrl("ISteamUser", "GetPlayerSummaries", "v2", {
                key: root.host.apiKey,
                steamids: chunk.join(",")
            }), sumJson => {
                if (g !== root.host.gen)
                    return;
                const players = sumJson?.response?.players || [];
                let online = 0;
                let inGame = 0;
                const preview = [];
                for (let i = 0; i < players.length; i++) {
                    const p = players[i];
                    const state = p.personastate ?? 0;
                    const playing = !!(p.gameextrainfo || p.gameid);
                    if (state > 0)
                        online++;
                    if (playing)
                        inGame++;
                    if (state > 0 && preview.length < 8) {
                        preview.push({
                            name: p.personaname || "",
                            avatarUrl: p.avatarmedium || p.avatar || "",
                            gameExtraInfo: p.gameextrainfo || "",
                            inGame: playing
                        });
                    }
                }
                // Scale if we only sampled first 100
                if (ids.length > chunk.length && chunk.length > 0) {
                    const scale = ids.length / chunk.length;
                    online = Math.round(online * scale);
                    inGame = Math.round(inGame * scale);
                }
                root.host.friendsOnline = online;
                root.host.friendsInGame = inGame;
                root.host.friendsPreview = preview;
                done();
            }, () => {
                if (g !== root.host.gen)
                    return;
                root.host.friendsOnline = -1;
                root.host.friendsInGame = -1;
                root.host.friendsPreview = [];
                root.host.friendsError = Tr.tr("Could not load friend status");
                done();
            });
        }, () => {
            if (g !== root.host.gen)
                return;
            root.host.friendsTotal = -1;
            root.host.friendsOnline = -1;
            root.host.friendsInGame = -1;
            root.host.friendsPreview = [];
            root.host.friendsError = Tr.tr("Friends list is private");
            done();
        });
    }
}
