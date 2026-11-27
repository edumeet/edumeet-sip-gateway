#!/bin/bash
# Clones SIPMediaGW at the version in SIPMEDIAGW_VERSION, packs the gateway assets, and loads the
# Kamailio and proxy images of that version from the build server.
# Run it before the first start and after a change of SIPMEDIAGW_VERSION or assets/.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -f "$repo_dir/central/.env" ]; then
    echo "Create central/.env from central/.env.example first." >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
. "$repo_dir/central/.env"
set +a

ref="$(tr -d '[:space:]' < "$repo_dir/SIPMEDIAGW_VERSION")"
if [ ! -d "$SIPMEDIAGW_DIR/.git" ]; then
    git clone "${SIPMEDIAGW_REPO:-https://github.com/edumeet/edumeet-sipmediagw.git}" "$SIPMEDIAGW_DIR"
fi
git -C "$SIPMEDIAGW_DIR" fetch --quiet --tags origin
git -C "$SIPMEDIAGW_DIR" checkout --quiet --force "$ref"

sh "$repo_dir/build-assets.sh"
bash "$repo_dir/fetch-images.sh" edumeet-sip-kamailio edumeet-sip-proxy
