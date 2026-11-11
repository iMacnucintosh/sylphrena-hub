#!/bin/bash
# Publish the zip of an extension as a GitHub release (tag <id>-<version>), if that tag is new.
#   scripts/publish.sh vpn-forticlient
# Run scripts/build.py first and commit index.json: it points at the release asset.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
id="${1:?usage: publish.sh <extension id>}"
version="$(python3 -c "import json,sys;print(json.load(open('extensions/$id/manifest.json'))['version'])")"
tag="$id-$version"
zip="dist/$tag.zip"
[ -f "$zip" ] || { echo "$zip not found: run scripts/build.py" >&2; exit 1; }
if gh release view "$tag" >/dev/null 2>&1; then
  echo "release $tag already exists: bump the version in the manifest to publish a new one" >&2
  exit 1
fi
gh release create "$tag" "$zip" --title "$id $version" --notes "Sylphrena extension $id $version. Install it from Nexus → Extensions → Install from zip."
echo "published $tag"
