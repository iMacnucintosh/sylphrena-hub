import QtQuick
import qs.components.images

// Steam artwork that survives missing images: some apps have no header.jpg on the CDN (404) but do
// have a library hero or a capsule. Tries each candidate in order when one fails to load.
FadeImage {
    id: root

    // URLs in order of preference (see Steam.artCandidates)
    property var candidates: []
    property int tryIdx: 0

    source: candidates[tryIdx] ?? ""

    onCandidatesChanged: tryIdx = 0
    onStatusChanged: {
        if (status === Image.Error && tryIdx < candidates.length - 1)
            tryIdx++;
    }
}
