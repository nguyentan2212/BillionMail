#!/bin/sh
set -eu

umask 022
state="${STATE_DIR:-/state}"
version="${BILLIONMAIL_CONFIG_VERSION:-unknown}"
sync_mode="${BILLIONMAIL_CONFIG_SYNC:-missing}"
env_recreate="${BILLIONMAIL_ENV_RECREATE:-false}"

: "${ADMIN_USERNAME:?ADMIN_USERNAME is required}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD is required}"
: "${SafePath:?SafePath is required}"
: "${BILLIONMAIL_HOSTNAME:?BILLIONMAIL_HOSTNAME is required}"
: "${DBHOST:?DBHOST is required}"
: "${DBPASS:?DBPASS is required}"
: "${REDISHOST:?REDISHOST is required}"
: "${REDISPASS:?REDISPASS is required}"

mkdir -p \
  "$state/conf" \
  "$state/conf/askai" \
  "$state/ssl-self-signed" \
  "$state/rspamd-data" \
  "$state/rspamd-data/dkim" \
  "$state/logs/rspamd" \
  "$state/logs/dovecot" \
  "$state/logs/postfix" \
  "$state/logs/fail2ban" \
  "$state/logs/core" \
  "$state/ssl" \
  "$state/vmail-data" \
  "$state/postfix-data" \
  "$state/webmail-data" \
  "$state/php-sock" \
  "$state/core-data"

chmod 0755 "$state/conf/askai" "$state/rspamd-data/dkim"

marker="$state/.dokploy-init-version"

if [ ! -s "$marker" ]; then
  echo "Initializing BillionMail persistent configuration from ${version}"
  rsync -a /seed/conf/ "$state/conf/"
  rsync -a /seed/ssl-self-signed/ "$state/ssl-self-signed/"
else
  previous="$(cat "$marker" 2>/dev/null || true)"
  echo "BillionMail state already exists (previous config: ${previous:-unknown})"

  case "$sync_mode" in
    none)
      echo "Config sync disabled"
      ;;
    missing)
      rsync -a --ignore-existing /seed/conf/ "$state/conf/"
      rsync -a --ignore-existing /seed/ssl-self-signed/ "$state/ssl-self-signed/"
      ;;
    overwrite)
      rsync -a --delete /seed/conf/ "$state/conf/"
      rsync -a --delete /seed/ssl-self-signed/ "$state/ssl-self-signed/"
      ;;
    *)
      echo "Unsupported BILLIONMAIL_CONFIG_SYNC=${sync_mode}" >&2
      exit 2
      ;;
  esac
fi

if [ ! -s "$state/.env" ] || [ "$env_recreate" = "true" ]; then
  tmp="$state/.env.tmp.$$"
  umask 077
  cat > "$tmp" <<ENVEOF
ADMIN_USERNAME=${ADMIN_USERNAME}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
SafePath=${SafePath}
BILLIONMAIL_HOSTNAME=${BILLIONMAIL_HOSTNAME}
DBHOST=${DBHOST}
DBPORT=${DBPORT:-5432}
DBNAME=${DBNAME:-billionmail}
DBUSER=${DBUSER:-billionmail}
DBPASS=${DBPASS}
DB_SSLMODE=${DB_SSLMODE:-disable}
REDISHOST=${REDISHOST}
REDISPORT=${REDISPORT:-6379}
REDISUSER=${REDISUSER:-}
REDISPASS=${REDISPASS}
REDISDB=${REDISDB:-1}
REDIS_TLS=${REDIS_TLS:-false}
REDIS_TLS_VERIFY=${REDIS_TLS_VERIFY:-required}
REDIS_TLS_SERVER_NAME=${REDIS_TLS_SERVER_NAME:-}
RSPAMD_REDISDB=${RSPAMD_REDISDB:-0}
SMTP_PORT=${SMTP_PORT:-25}
SMTPS_PORT=${SMTPS_PORT:-465}
SUBMISSION_PORT=${SUBMISSION_PORT:-587}
IMAP_PORT=${IMAP_PORT:-143}
IMAPS_PORT=${IMAPS_PORT:-993}
POP_PORT=${POP_PORT:-110}
POPS_PORT=${POPS_PORT:-995}
HTTP_PORT=${HTTP_PORT:-8080}
HTTPS_PORT=${HTTPS_PORT:-8443}
WEB_BASE_PATH=${WEB_BASE_PATH:-}
AAPANEL_SSO_SECRET=${AAPANEL_SSO_SECRET:-}
TZ=${TZ:-Asia/Ho_Chi_Minh}
IPV4_NETWORK=${IPV4_NETWORK:-10.89.0}
FAIL2BAN_INIT=${FAIL2BAN_INIT:-y}
IP_WHITELIST_ENABLE=${IP_WHITELIST_ENABLE:-false}
RETENTION_DAYS=${RETENTION_DAYS:-7}
ENVEOF
  chmod 0600 "$tmp"
  mv -f "$tmp" "$state/.env"
  umask 022
  echo "Persistent BillionMail .env created"
else
  echo "Persistent BillionMail .env preserved"
fi

sync_env_key() {
  key="$1"
  value="$2"
  tmp="$state/.env.sync.$$"

  grep -v "^${key}=" "$state/.env" > "$tmp" || true
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$state/.env"
}

# Infrastructure settings are owned by Dokploy and are synchronized on every
# deployment. Admin credentials, SafePath and hostname remain persistent unless
# BILLIONMAIL_ENV_RECREATE=true is used intentionally.
sync_env_key DBHOST "${DBHOST}"
sync_env_key DBPORT "${DBPORT:-5432}"
sync_env_key DBNAME "${DBNAME:-billionmail}"
sync_env_key DBUSER "${DBUSER:-billionmail}"
sync_env_key DBPASS "${DBPASS}"
sync_env_key DB_SSLMODE "${DB_SSLMODE:-disable}"
sync_env_key REDISHOST "${REDISHOST}"
sync_env_key REDISPORT "${REDISPORT:-6379}"
sync_env_key REDISUSER "${REDISUSER:-}"
sync_env_key REDISPASS "${REDISPASS}"
sync_env_key REDISDB "${REDISDB:-1}"
sync_env_key REDIS_TLS "${REDIS_TLS:-false}"
sync_env_key REDIS_TLS_VERIFY "${REDIS_TLS_VERIFY:-required}"
sync_env_key REDIS_TLS_SERVER_NAME "${REDIS_TLS_SERVER_NAME:-}"
sync_env_key RSPAMD_REDISDB "${RSPAMD_REDISDB:-0}"

printf '%s\n' "$version" > "$marker"
echo "BillionMail initialization completed"
