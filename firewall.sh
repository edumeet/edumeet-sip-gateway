#!/bin/bash
# Sets ufw on a central host or a gateway host, as on the eduMEET media nodes: IPv4 rules
# only, and all IPv6 refused. Run as root: firewall.sh central, or firewall.sh gateway.
# It replaces all ufw rules on the host.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
role="${1:-}"
case "$role" in
    central) env_file="$repo_dir/central/.env" ;;
    gateway) env_file=/etc/edumeet-sip-gateway/gateway.env ;;
    *) echo "Usage: $0 central|gateway" >&2; exit 1 ;;
esac
set -a
# shellcheck source=/dev/null
. "$env_file"
set +a
: "${SSH_SOURCES:?Set SSH_SOURCES in $env_file}"
if [ "$role" = gateway ]; then
    : "${CENTRAL_IP:?Set CENTRAL_IP in $env_file}"
fi

read -ra ssh_sources <<< "$SSH_SOURCES"

# Do not cut off the SSH session that runs this script.
client="${SSH_CONNECTION:-}"
client="${client%% *}"
if [ -z "$client" ]; then
    client="$(who -m 2>/dev/null | sed -n 's/.*(\([0-9a-fA-F.:]*\)).*/\1/p')"
fi
if [[ "$client" == *:* ]]; then
    echo "You are connected over IPv6, which this firewall refuses. Connect over IPv4 first." >&2
    exit 1
fi
if [ -n "$client" ] && ! printf '%s\n' "${ssh_sources[@]}" | grep -qxF "$client"; then
    echo "Your SSH address $client is not in SSH_SOURCES. Add it to $env_file first." >&2
    exit 1
fi

if ! command -v ufw >/dev/null; then
    apt-get install -y ufw
fi

ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw deny in from ::/0 to ::/0

for source in "${ssh_sources[@]}"; do
    ufw allow in proto tcp from "$source" to 0.0.0.0/0 port 22
done
ufw allow in proto tcp from 0.0.0.0/0 to 0.0.0.0/0 port 80
if [ "$role" = central ]; then
    ufw allow in proto tcp from 0.0.0.0/0 to 0.0.0.0/0 port 443
    ufw allow in proto tcp from 0.0.0.0/0 to 0.0.0.0/0 port 5060
    ufw allow in proto udp from 0.0.0.0/0 to 0.0.0.0/0 port 5060
    ufw allow in proto tcp from 0.0.0.0/0 to 0.0.0.0/0 port 5061
else
    ufw allow in proto tcp from "$CENTRAL_IP" to 0.0.0.0/0 port 443
fi

ufw --force enable
ufw status verbose
