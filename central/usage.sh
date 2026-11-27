#!/bin/bash
# Shows the gateways that are registered with Kamailio, per gateway host, and which of them are
# busy: the usage, and when update.sh can run without ending a call. Run as root on the central
# host. With -w it shows the state again every 5 seconds (or every N seconds: -w N), until Ctrl-C.

set -euo pipefail

show() {
    local prefix rows
    prefix="$(docker exec kamailio printenv GW_NAME_PREFIX 2>/dev/null || true)"
    prefix="${prefix:-mediagw}"
    if [[ ! "$prefix" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "Unexpected GW_NAME_PREFIX: $prefix" >&2
        return 1
    fi
    # One row per gateway: a gateway that registers again after a call can have a second,
    # older contact for a short time, and the newer one decides. baresip puts "<user>-<pointer>"
    # in its Contact, so the "-" keeps gw1 from matching the calls of gw10.
    if ! rows="$(docker exec -i kamailioDB sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B kamailio' <<SQL
SELECT l.username,
       MAX(SUBSTRING_INDEX(SUBSTRING_INDEX(COALESCE(NULLIF(l.received, ''), l.contact), 'sip:', -1), ':', 1)),
       MIN(l.locked),
       COALESCE(MAX(d.state), 0),
       COALESCE(UNIX_TIMESTAMP() - MIN(NULLIF(d.start_time, 0)), 0),
       COALESCE(MAX(d.from_uri), '')
FROM location l
LEFT JOIN dialog d ON d.callee_contact LIKE CONCAT('%', l.username, '-%')
WHERE l.username LIKE '%${prefix}%' AND l.expires > NOW()
GROUP BY l.username;
SQL
)"; then
        echo "Cannot read the Kamailio database: is the kamailioDB container running?" >&2
        return 1
    fi

    date -u '+SIP gateways, %Y-%m-%d %H:%M:%S UTC'
    echo
    if [ -z "$rows" ]; then
        echo "No gateway is registered."
        return 0
    fi
    printf '%s\n' "$rows" | awk -F '\t' -v prefix="$prefix" '
        function duration(s) {
            if (s >= 3600) return sprintf("%d h %02d min", int(s / 3600), int((s % 3600) / 60))
            if (s >= 60) return sprintf("%d min", int(s / 60))
            return sprintf("%d s", s)
        }
        function caller(uri) {
            sub(/^[^<]*</, "", uri)
            sub(/^sips?:/, "", uri)
            sub(/[;>].*$/, "", uri)
            return uri
        }
        {
            user = $1; ip = $2; locked = $3 + 0; state = $4 + 0; secs = $5 + 0; from = $6
            n = index(user, "." prefix ".")
            host = n ? substr(user, 1, n - 1) : ip
            gw = user; sub(/^.*\./, "", gw)
            if (state >= 3) { what = "in a call for " duration(secs) ", from " caller(from); calls[host]++ }
            else if (state > 0) { what = "call starting, from " caller(from); calls[host]++ }
            else if (locked) { what = "busy without a call: a call is being set up, or it restarts after one"; busy[host]++ }
            else { what = "free"; free[host]++ }
            if (!(host in seen)) { seen[host] = 1; hosts[++nh] = host; ips[host] = ip }
            count[host]++
            line[host, gw + 0] = sprintf("  gw%-3s %s", gw, what)
            if (gw + 0 > maxgw[host]) maxgw[host] = gw + 0
        }
        END {
            for (i = 1; i <= nh; i++) {
                h = hosts[i]
                printf "%s (%s): %d registered, %d in a call, %d busy, %d free\n", h, ips[h], count[h], calls[h], busy[h], free[h]
                for (g = 0; g <= maxgw[h]; g++) if ((h, g) in line) print line[h, g]
                if (calls[h] + busy[h] > 0)
                    printf "  -> wait: update.sh on this host now ends the calls on it\n\n"
                else
                    printf "  -> no calls: update.sh on this host is safe now\n\n"
                tc += calls[h]; tb += busy[h]; tf += free[h]; tr += count[h]
            }
            printf "Total: %d registered, %d in a call, %d busy, %d free\n", tr, tc, tb, tf
            if (tc + tb > 0)
                print "Central host: update.sh restarts Kamailio for all hosts: wait, calls are running."
            else
                print "Central host: no calls: update.sh is safe now."
            print "A gateway that has just ended a call is missing for about 15 s while it starts again."
        }'
}

if [ "${1:-}" = "-w" ]; then
    interval="${2:-5}"
    while true; do
        out="$(show 2>&1)" || true
        clear
        printf '%s\n' "$out"
        sleep "$interval"
    done
fi
show
