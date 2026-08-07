#!/bin/bash
set -e

: "${REDISHOST:?REDISHOST is required}"
: "${REDISPASS:?REDISPASS is required}"

REDISPORT="${REDISPORT:-6379}"
REDISUSER="${REDISUSER:-}"
RSPAMD_REDISDB="${RSPAMD_REDISDB:-0}"

if [ "${REDIS_TLS:-false}" = "true" ]; then
  echo "Rspamd direct Redis TLS is not supported by this simplified deployment." >&2
  echo "Use a private plaintext Redis endpoint or add a dedicated TLS tunnel." >&2
  exit 1
fi

if ! grep -q "rotate_log.sh" /var/spool/cron/crontabs/root; then
    chmod +x /rotate_log.sh
    echo "10 00 * * * bash /rotate_log.sh >> /var/log/rspamd/rotate_log.log 2>&1" >> /var/spool/cron/crontabs/root
    chmod 600 /var/spool/cron/crontabs/root
    chown root:crontab /var/spool/cron/crontabs/root 2>/dev/null || chown root:root /var/spool/cron/crontabs/root
    /usr/bin/supervisorctl restart cron
fi

chmod 755 /var/lib/rspamd
chown -R _rspamd:_rspamd /var/lib/rspamd

cat <<EOF > /etc/rspamd/local.d/redis.conf
servers = "${REDISHOST}:${REDISPORT}";
disabled_modules = ["ratelimit"];
timeout = 10s;
db = "${RSPAMD_REDISDB}";
password = "${REDISPASS}";
EOF

if [ -n "${REDISUSER}" ]; then
  printf 'username = "%s";\n' "${REDISUSER}" >> /etc/rspamd/local.d/redis.conf
fi

exec "$@"
