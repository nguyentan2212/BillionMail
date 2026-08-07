#!/bin/sh
set -eu

: "${REDISHOST:?REDISHOST is required}"
: "${REDISPASS:?REDISPASS is required}"

REDISPORT="${REDISPORT:-6379}"
REDIS_TLS="${REDIS_TLS:-false}"
REDIS_TLS_VERIFY="${REDIS_TLS_VERIFY:-required}"
REDIS_TLS_SERVER_NAME="${REDIS_TLS_SERVER_NAME:-$REDISHOST}"

case "$REDISHOST" in
  *[!A-Za-z0-9_.:-]*)
    echo "REDISHOST contains unsupported characters" >&2
    exit 2
    ;;
esac

case "$REDISPORT" in
  ''|*[!0-9]*)
    echo "REDISPORT must be numeric" >&2
    exit 2
    ;;
esac

case "$REDIS_TLS" in
  true|false) ;;
  *)
    echo "REDIS_TLS must be true or false" >&2
    exit 2
    ;;
esac

case "$REDIS_TLS_VERIFY" in
  required|none) ;;
  *)
    echo "REDIS_TLS_VERIFY must be required or none" >&2
    exit 2
    ;;
esac

case "$REDIS_TLS_SERVER_NAME" in
  *[!A-Za-z0-9_.:-]*)
    echo "REDIS_TLS_SERVER_NAME contains unsupported characters" >&2
    exit 2
    ;;
esac

server_host="$REDISHOST"
case "$server_host" in
  *:*) server_host="[$server_host]" ;;
esac

tls_options=""
if [ "$REDIS_TLS" = "true" ]; then
  if [ "$REDIS_TLS_VERIFY" = "required" ]; then
    tls_options="ssl verify required ca-file /etc/ssl/certs/ca-certificates.crt sni str(${REDIS_TLS_SERVER_NAME})"
  else
    tls_options="ssl verify none sni str(${REDIS_TLS_SERVER_NAME})"
  fi
fi

cat > /etc/haproxy/haproxy.cfg <<EOF_CONFIG
global
    log stdout format raw local0
    maxconn 4096

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 10s
    timeout client 1h
    timeout server 1h
    timeout check 5s

resolvers docker
    nameserver dns 127.0.0.11:53
    resolve_retries 3
    timeout resolve 1s
    timeout retry 1s
    hold other 10s
    hold refused 10s
    hold nx 10s
    hold timeout 10s
    hold valid 10s
    hold obsolete 10s

frontend redis_in
    bind 0.0.0.0:6379
    default_backend redis_out

backend redis_out
    server redis_upstream ${server_host}:${REDISPORT} check inter 5s fall 3 rise 2 resolvers docker init-addr last,libc,none ${tls_options}
EOF_CONFIG

exec haproxy -W -db -f /etc/haproxy/haproxy.cfg
