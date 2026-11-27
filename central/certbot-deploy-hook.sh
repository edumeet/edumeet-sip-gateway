#!/bin/sh
# certbot runs this after it gets or renews the certificate of the central host
# (--deploy-hook). It copies the certificate for Kamailio, then loads it in nginx
# and in Kamailio without a restart.

set -eu

tls_dir="$(cd "$(dirname "$0")" && pwd)/tls"
install -d -m 700 "$tls_dir"
install -m 644 "$RENEWED_LINEAGE/fullchain.pem" "$tls_dir/cert.pem"
install -m 600 "$RENEWED_LINEAGE/privkey.pem" "$tls_dir/key.pem"

systemctl reload nginx
if [ -n "$(docker ps --quiet --filter name='^kamailio$')" ]; then
    docker exec kamailio kamcmd tls.reload
fi
