#!/bin/bash
# Shows the addresses that fail2ban blocks now, per jail, and when each ban ends: the two SIP jails
# (see "Block SIP scanners" in README.md) and the other jails of the host, such as sshd. Run as
# root on the central host.

set -euo pipefail

if ! command -v fail2ban-client >/dev/null; then
    echo "fail2ban is not installed. See \"Block SIP scanners\" in README.md." >&2
    exit 1
fi
if ! status="$(fail2ban-client status 2>/dev/null)"; then
    echo "Cannot reach fail2ban: run as root, and check 'systemctl status fail2ban'." >&2
    exit 1
fi
jails="$(printf '%s\n' "$status" | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' ')"

date '+Blocked by fail2ban, %Y-%m-%d %H:%M:%S %Z'
echo
if [ -z "${jails// /}" ]; then
    echo "fail2ban has no jails."
    exit 0
fi

declare -A all=()
for jail in $jails; do
    # One line per address: "<address>  <start date> <start time> + <seconds> = <end date> <end time>".
    bans="$(fail2ban-client get "$jail" banip --with-time | awk 'NF >= 8' | sort -k7,8)"
    if [ -z "$bans" ]; then
        echo "$jail: none"
        echo
        continue
    fi
    echo "$jail: $(printf '%s\n' "$bans" | wc -l) blocked"
    printf '%s\n' "$bans" | awk '{ printf "  %-15s  until %s %s (since %s %s)\n", $1, $7, $8, $2, $3 }'
    echo
    while read -r address _; do
        all["$address"]=1
    done <<< "$bans"
done
if [ "${#all[@]}" -eq 1 ]; then
    echo "Total: 1 address blocked"
else
    echo "Total: ${#all[@]} addresses blocked"
fi
