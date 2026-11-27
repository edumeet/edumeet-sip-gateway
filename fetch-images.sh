#!/bin/bash
# Loads images of the SIPMediaGW version in SIPMEDIAGW_VERSION from the build server, and tags
# each one <name>:local. Usage: IMAGES_URL=... fetch-images.sh <name>...
# The build server builds them with edumeet-sip-gateway/build_and_publish.sh and writes the
# version it built in current_sip_version.txt.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${IMAGES_URL:?Set IMAGES_URL}"

ref="$(tr -d '[:space:]' < "$repo_dir/SIPMEDIAGW_VERSION")"
built="$(curl -fsSL --max-time 15 "$IMAGES_URL/current_sip_version.txt" | tr -d '[:space:]')" || {
    echo "Cannot read $IMAGES_URL/current_sip_version.txt." >&2
    exit 1
}
if [ "$built" != "$ref" ]; then
    echo "The build server has the images of $built, but SIPMEDIAGW_VERSION is $ref." >&2
    echo "Run build_and_publish.sh on the build server, or git pull in $repo_dir." >&2
    exit 1
fi

for name in "$@"; do
    echo "Loading $name $ref..."
    if ! curl -fsSL "$IMAGES_URL/${name}_${ref}.tar" | docker load; then
        echo "Cannot load $IMAGES_URL/${name}_${ref}.tar." >&2
        exit 1
    fi
    docker tag "edumeet/$name:$ref" "$name:local"
done
