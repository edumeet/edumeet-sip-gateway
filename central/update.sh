#!/bin/bash
# Updates the central host: git pull, central/prepare.sh (SIPMediaGW checkout, gateway assets and the
# images of SIPMEDIAGW_VERSION), the containers whose image changed, then removes the images that no
# container uses.
# --renew-anon-volumes because the Kamailio base image keeps its configuration in an anonymous volume
# (/etc/kamailio), which docker compose otherwise keeps from the old container. The MySQL data is in
# the named volume kamailio_db and stays.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run the pulled version of this script for the rest.
if [ "${1:-}" != "--pulled" ]; then
    git -C "$repo_dir" pull --ff-only
    exec "$repo_dir/central/update.sh" --pulled
fi

"$repo_dir/central/prepare.sh"
cd "$repo_dir/central"
docker compose up -d --renew-anon-volumes
docker compose ps
echo "Removing the images that no container uses..."
docker image prune -a -f
