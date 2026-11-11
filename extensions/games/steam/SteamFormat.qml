pragma ComponentBehavior: Bound

import QtQuick
import Sylphrena.I18n

// Pure presentation helpers for the Steam façade (no network / no Process).
QtObject {
    id: root

    // Steam singleton façade — needed for nonSteamGames art lookup + Tr locale.
    required property var host

    function steamLang(): string {
        const name = Tr.locale.name || "en_US";
        const [lang, region] = name.split("_");
        const map = {
            es: region && region !== "ES" ? "latam" : "spanish",
            pt: region === "BR" ? "brazilian" : "portuguese",
            zh: region === "TW" || region === "HK" ? "tchinese" : "schinese",
            fr: "french",
            de: "german",
            it: "italian",
            ru: "russian",
            ja: "japanese",
            ko: "koreana",
            pl: "polish",
            nl: "dutch",
            tr: "turkish",
            uk: "ukrainian"
        };
        return map[lang] ?? "english";
    }

    function capsuleUrl(appId: string): string {
        if (!appId)
            return "";
        const local = root.host.nonSteamGames.find(g => g.appId === appId);
        if (local?.capsuleUrl)
            return local.capsuleUrl;
        return `https://cdn.cloudflare.steamstatic.com/steam/apps/${appId}/capsule_184x69.jpg`;
    }

    function headerUrl(appId: string): string {
        if (!appId)
            return "";
        const local = root.host.nonSteamGames.find(g => g.appId === appId);
        if (local?.headerUrl)
            return local.headerUrl;
        return `https://cdn.cloudflare.steamstatic.com/steam/apps/${appId}/header.jpg`;
    }

    // Header image first, then other artwork of the same app: some apps have no header.jpg (404)
    // but do have a library hero or a capsule. Non-Steam games only have their local grid image.
    function artCandidates(appId: string, preferred: string): var {
        const out = [];
        if (preferred)
            out.push(preferred);
        else if (appId)
            out.push(root.headerUrl(appId));
        const local = appId ? root.host.nonSteamGames.find(g => g.appId === appId) : null;
        if (appId && !local) {
            const base = `https://cdn.cloudflare.steamstatic.com/steam/apps/${appId}/`;
            for (const f of ["library_hero.jpg", "capsule_616x353.jpg", "capsule_231x87.jpg", "library_600x900.jpg"])
                out.push(base + f);
        }
        return out;
    }

    function formatPlaytime(minutes: int): string {
        if (!minutes || minutes <= 0)
            return Tr.tr("No playtime");
        if (minutes < 60)
            return Tr.tr("%1 min").arg(minutes);
        const hours = Math.floor(minutes / 60);
        const rem = minutes % 60;
        if (hours < 100 && rem > 0)
            return Tr.tr("%1 h %2 min").arg(hours).arg(rem);
        return Tr.tr("%1 h").arg(hours);
    }

    function personaStateLabel(): string {
        const profile = root.host.profile;
        const state = profile?.personaState;
        if (profile?.gameExtraInfo)
            return Tr.tr("In-game");
        if (state === 1)
            return Tr.tr("Online");
        if (state === 2)
            return Tr.tr("Busy");
        if (state === 3)
            return Tr.tr("Away");
        if (state === 4)
            return Tr.tr("Snooze");
        if (state === 5)
            return Tr.tr("Looking to trade");
        if (state === 6)
            return Tr.tr("Looking to play");
        return Tr.tr("Offline");
    }

    function extractSteamIdOrVanity(raw: string): var {
        const s = (raw || "").trim();
        if (!s)
            return { kind: "empty" };

        const profiles = s.match(/steamcommunity\.com\/profiles\/(\d+)/i);
        if (profiles)
            return { kind: "id", value: profiles[1] };

        const vanity = s.match(/steamcommunity\.com\/id\/([^\/\?#]+)/i);
        if (vanity)
            return { kind: "vanity", value: decodeURIComponent(vanity[1]) };

        if (/^\d{17}$/.test(s))
            return { kind: "id", value: s };

        return { kind: "vanity", value: s.replace(/^\/+|\/+$/g, "") };
    }
}
