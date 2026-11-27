#!/bin/sh
# Writes TURN REST API credentials (an expiry time in the user name, an HMAC-SHA1 of
# it with the shared secret as password) into the env file SIPMediaGW gives to every
# gateway container. coturn checks them with --use-auth-secret.
# A gateway container reads the file when it is created, and it is created again only
# after a call. A gateway can wait weeks for its next call, so the credentials stay
# valid for a year.

set -eu

: "${SIPMEDIAGW_DIR:?}" "${GATEWAY_TURN_SECRET:?}"

ttl="${TURN_CREDENTIAL_TTL:-31536000}"
user="$(( $(date +%s) + ttl )):${TURN_USER_NAME:-sipgw}"
pass="$(printf '%s' "$user" | openssl dgst -sha1 -hmac "$GATEWAY_TURN_SECRET" -binary | base64)"

target="$SIPMEDIAGW_DIR/deploy/coturn/.env_cred"
umask 077
printf 'TURN_USER=%s\nTURN_PASS=%s\n' "$user" "$pass" > "$target.tmp"
mv "$target.tmp" "$target"
