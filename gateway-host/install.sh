#!/bin/bash
# Prepares an Ubuntu host to run SIPMediaGW gateways for eduMEET. Run as root.
# Run it again after a change of SIPMEDIAGW_VERSION, sipmediagw.env, webrtc_domains.json or gateway.env.
# --update (from gateway-host/update.sh): leaves ufw as it is.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
update=false
[ "${1:-}" = "--update" ] && update=true
env_file=/etc/edumeet-sip-gateway/gateway.env

if [ ! -f "$env_file" ]; then
    echo "Create $env_file from gateway-host/gateway.env.example first." >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
. "$env_file"
set +a

if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
    echo "Install Docker Engine with the compose plugin first." >&2
    exit 1
fi

apt-get update
# snd-aloop is in linux-modules-extra up to Ubuntu 24.04, and in linux-modules
# (installed with the kernel) from Ubuntu 26.04.
packages=("linux-headers-$(uname -r)" v4l2loopback-dkms python3-venv git jq bc openssl ufw curl)
if ! modinfo snd-aloop >/dev/null 2>&1; then
    packages+=("linux-modules-extra-$(uname -r)")
fi
apt-get install -y "${packages[@]}"

ref="$(tr -d '[:space:]' < "$repo_dir/SIPMEDIAGW_VERSION")"
if [ ! -d "$SIPMEDIAGW_DIR/.git" ]; then
    git clone "${SIPMEDIAGW_REPO:-https://github.com/edumeet/edumeet-sipmediagw.git}" "$SIPMEDIAGW_DIR"
fi
git -C "$SIPMEDIAGW_DIR" fetch --quiet --tags origin
git -C "$SIPMEDIAGW_DIR" checkout --quiet --force "$ref"

# The list of this repository, so that update.sh applies its changes. gateway.env can name another file.
WEBRTC_DOMAINS_FILE="${WEBRTC_DOMAINS_FILE:-$repo_dir/gateway-host/webrtc_domains.json}"
webrtc_domains="$(jq -ce 'if type == "object" and length > 0 and all(.[]; .domain) then . else error("each entry needs a domain") end' "$WEBRTC_DOMAINS_FILE")" || {
    echo "$WEBRTC_DOMAINS_FILE must be a JSON object of webrtc_domains entries." >&2
    exit 1
}
webrtc_domains="$(printf '%s' "$webrtc_domains" | sed 's/[&|\\]/\\&/g')"
sed "s|@WEBRTC_DOMAINS@|$webrtc_domains|" "$repo_dir/gateway-host/sipmediagw.env" > "$SIPMEDIAGW_DIR/.env"

# Upstream documents a /29, which holds five containers; eight gateways need a /28.
if ! docker network inspect gw_net >/dev/null 2>&1; then
    docker network create --subnet=192.168.92.0/28 gw_net
fi

bash "$repo_dir/fetch-images.sh" edumeet-sip-gateway

python3 -m venv "$repo_dir/.venv"
"$repo_dir/.venv/bin/pip" install --quiet fastapi uvicorn

chmod 755 "$repo_dir/gateway-host/start.sh" "$repo_dir/gateway-host/turn-credentials.sh" "$repo_dir/firewall.sh"
for unit in edumeet-sip-gateway.service edumeet-sip-turn-credentials.service edumeet-sip-turn-credentials.timer; do
    sed "s|@REPO_DIR@|$repo_dir|g" "$repo_dir/gateway-host/systemd/$unit" > "/etc/systemd/system/$unit"
done
systemctl daemon-reload
if [ "$update" = false ]; then
    "$repo_dir/firewall.sh" gateway
fi
systemctl enable --now edumeet-sip-turn-credentials.timer
systemctl enable edumeet-sip-gateway.service
systemctl restart edumeet-sip-gateway.service
