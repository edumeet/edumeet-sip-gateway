#!/bin/sh
# Packs the gateway assets into build/assets.tar.xz: the branding in assets/gateway and the eduMEET
# connector of the SIPMediaGW checkout. The proxy serves the file, and every gateway container
# unpacks it into its browsing assets when it starts (ASSETS_URL), so a new connector reaches the
# gateways without a rebuild of their image.

set -eu

repo_dir="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${SIPMEDIAGW_DIR:-}" ] && [ -f "$repo_dir/central/.env" ]; then
    # shellcheck source=/dev/null
    . "$repo_dir/central/.env"
fi
: "${SIPMEDIAGW_DIR:?}"

connector="$SIPMEDIAGW_DIR/browsing/assets/edumeet.js"
if [ ! -f "$connector" ]; then
    echo "$connector is missing. Run central/prepare.sh first." >&2
    exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$repo_dir/assets/gateway/." "$stage/"
cp "$connector" "$stage/edumeet.js"

mkdir -p "$repo_dir/build"
tar -cJf "$repo_dir/build/assets.tar.xz" -C "$stage" .
echo "Wrote $repo_dir/build/assets.tar.xz"
