#!/bin/bash
# Derived from SIPMediaGW deploy/services/start_all_gateways.bash (Apache-2.0).
# Changes: the number of loopback devices follows the number of gateway slots,
# the TURN credentials are written before the first gateway starts, the
# gateways register with the central proxy given in GW_PROXY, and HTTPLauncher
# listens on LAUNCHER_HOST:LAUNCHER_PORT, behind nginx.

set -u

: "${SIPMEDIAGW_DIR:?}" "${GW_PROXY:?}" "${HOST_IP:?}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
launcher_python="${LAUNCHER_PYTHON:-$script_dir/../.venv/bin/python}"
launcher_host="${LAUNCHER_HOST:-127.0.0.1}"
launcher_port="${LAUNCHER_PORT:-8100}"

cd "$SIPMEDIAGW_DIR" || exit 1

cpu_per_gw=$(docker compose config 2>/dev/null | awk '/CPU_PER_GW:/ {print $2}' | tr -d '"')
gw_count=$(( $(nproc) / cpu_per_gw ))
if [ "$gw_count" -lt 1 ]; then
    echo "Not enough CPUs for one gateway: $(nproc) CPUs, $cpu_per_gw per gateway" >&2
    exit 1
fi
# The launcher publishes chromedriver on port 951<slot>, so slots stop at 9.
if [ "$gw_count" -gt 10 ]; then
    echo "At most 10 gateways per host: lower the vCPUs or raise CPU_PER_GW" >&2
    exit 1
fi

"$script_dir/turn-credentials.sh" || exit 1

ones() { printf '1%.0s,' $(seq 1 "$1") | sed 's/,$//'; }
echo "options snd-aloop enable=$(ones $((gw_count * 2))) index=$(seq -s, 0 $((gw_count * 2 - 1)))" \
    > /etc/modprobe.d/alsa-loopback.conf
echo "options v4l2loopback devices=$gw_count exclusive_caps=$(ones "$gw_count")" \
    > /etc/modprobe.d/v4l2loopback.conf
modprobe -r snd-aloop 2>/dev/null; modprobe snd-aloop || exit 1
modprobe -r v4l2loopback 2>/dev/null; modprobe v4l2loopback || exit 1

"$launcher_python" HTTPLauncher.py --host "$launcher_host" --port "$launcher_port" 2>&1 | logger -t HTTPLauncher &

prefix="${PREFIX:-$HOST_IP}"
until [ "$?" == 1 ]; do
    cd "$SIPMEDIAGW_DIR" || exit 1
    /bin/bash ./SIPMediaGW.sh -p "$prefix" -l -y "$GW_PROXY"
done
exit 0
