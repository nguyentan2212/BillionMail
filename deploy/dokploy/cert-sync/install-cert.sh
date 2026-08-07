#!/bin/sh
set -eu

: "${BILLIONMAIL_HOSTNAME:?BILLIONMAIL_HOSTNAME is required}"

cert="/dump/${BILLIONMAIL_HOSTNAME}/cert.pem"
key="/dump/${BILLIONMAIL_HOSTNAME}/key.pem"

if [ ! -s "$cert" ] || [ ! -s "$key" ]; then
  echo "No Traefik certificate found for ${BILLIONMAIL_HOSTNAME}" >&2
  exit 0
fi

cp -f "$cert" /mailssl/cert.pem
cp -f "$key" /mailssl/key.pem
chmod 0644 /mailssl/cert.pem
chmod 0600 /mailssl/key.pem

marker="/mailssl/.reload.$$"
cat "$cert" "$key" | sha256sum | cut -d " " -f 1 > "$marker"
chmod 0644 "$marker"
mv -f "$marker" /mailssl/.reload
