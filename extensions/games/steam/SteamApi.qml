pragma ComponentBehavior: Bound

import QtQuick
import Sylphrena
import Sylphrena.I18n

// HTTP + vanity resolve for the Steam façade. Shares host.gen for cancellation.
QtObject {
    id: root

    required property var host

    function apiUrl(iface: string, method: string, version: string, params: var): string {
        const q = Object.keys(params).map(k => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`).join("&");
        return `https://api.steampowered.com/${iface}/${method}/${version}/?${q}`;
    }

    function getJson(url: string, ok: var, fail: var): void {
        Requests.get(url, text => {
            try {
                ok(JSON.parse(text));
            } catch (e) {
                if (fail)
                    fail(Tr.tr("Invalid Steam API response"));
            }
        }, err => {
            if (fail)
                fail(err || Tr.tr("Steam request failed"));
        });
    }

    function resolveVanity(vanity: string, g: int, ok: var, fail: var): void {
        const url = root.apiUrl("ISteamUser", "ResolveVanityURL", "v1", {
            key: root.host.apiKey,
            vanityurl: vanity
        });
        root.getJson(url, json => {
            if (g !== root.host.gen)
                return;
            const resp = json?.response;
            if (resp?.success === 1 && resp.steamid)
                ok(String(resp.steamid));
            else if (fail)
                fail(Tr.tr("Could not resolve Steam vanity URL"));
        }, err => {
            if (g !== root.host.gen)
                return;
            if (fail)
                fail(err);
        });
    }
}
