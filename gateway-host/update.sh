#!/bin/bash
# Updates a gateway host: git pull, gateway-host/install.sh --update (SIPMediaGW checkout and gateway
# image of SIPMEDIAGW_VERSION, restart of the gateways; ufw stays as it is), then removes the images
# that no container uses. Run as root. The restart stops the calls on this host.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run the pulled version of this script for the rest.
if [ "${1:-}" != "--pulled" ]; then
    git -C "$repo_dir" pull --ff-only
    exec "$repo_dir/gateway-host/update.sh" --pulled
fi

"$repo_dir/gateway-host/install.sh" --update

# Without a running gateway the prune would also remove the gateway image, and SIPMediaGW would build
# it for the next call.
if docker ps -q --filter ancestor=edumeet-sip-gateway:local | grep -q .; then
    echo "Removing the images that no container uses..."
    docker image prune -a -f
else
    echo "No gateway container runs, so the old images stay. See: journalctl -u edumeet-sip-gateway" >&2
    exit 1
fi
