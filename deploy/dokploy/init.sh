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
: "${DBPASS:?DBPASS is required}"
: "${REDISPASS:?REDISPASS is required}"

mkdir -p \
  "$state/conf" \
  "$state/conf/askai" \
  "$state/ssl-self-signed" \
  "$state/postgresql-data" \
  "$state/postgresql-socket" \
  "$state/redis-data" \
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
  "$state/core-data" \
  "$state/cert-dump"

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
      # Safe default: add files introduced by a newer release, but never replace
      # files that BillionMail or the operator may already have modified.
      rsync -a --ignore-existing /seed/conf/ "$state/conf/"
      rsync -a --ignore-existing /seed/ssl-self-signed/ "$state/ssl-self-signed/"
      ;;
    overwrite)
      # Use only after backup and review during an intentional upgrade.
      rsync -a --delete /seed/conf/ "$state/conf/"
      rsync -a --delete /seed/ssl-self-signed/ "$state/ssl-self-signed/"
      ;;
    *)
      echo "Unsupported BILLIONMAIL_CONFIG_SYNC=${sync_mode}" >&2
      exit 2
      ;;
  esac
fi

# BillionMail edits this file from its Settings UI (admin username/password,
# SafePath and hostname). Preserve it across normal redeployments.
if [ ! -s "$state/.env" ] || [ "$env_recreate" = "true" ]; then
  tmp="$state/.env.tmp.$$"
  umask 077
  cat > "$tmp" <<ENVEOF
ADMIN_USERNAME=${ADMIN_USERNAME}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
SafePath=${SafePath}
BILLIONMAIL_HOSTNAME=${BILLIONMAIL_HOSTNAME}
DBNAME=${DBNAME:-billionmail}
DBUSER=${DBUSER:-billionmail}
DBPASS=${DBPASS}
DBHOST=${DBHOST:-pgsql-billionmail}
DBPORT=${DBPORT:-5432}
DB_SSLMODE=${DB_SSLMODE:-disable}
DB_POOL_MODE=${DB_POOL_MODE:-session}
DB_MAX_CLIENT_CONN=${DB_MAX_CLIENT_CONN:-200}
DB_DEFAULT_POOL_SIZE=${DB_DEFAULT_POOL_SIZE:-20}
REDISPASS=${REDISPASS}
REDISHOST=${REDISHOST:-redis-billionmail}
REDISPORT=${REDISPORT:-6379}
REDIS_TLS=${REDIS_TLS:-false}
REDIS_TLS_VERIFY=${REDIS_TLS_VERIFY:-required}
REDIS_TLS_SERVER_NAME=${REDIS_TLS_SERVER_NAME:-}
REDISDB=${REDISDB:-1}
SMTP_PORT=${SMTP_PORT:-25}
SMTPS_PORT=${SMTPS_PORT:-465}
SUBMISSION_PORT=${SUBMISSION_PORT:-587}
IMAP_PORT=${IMAP_PORT:-143}
IMAPS_PORT=${IMAPS_PORT:-993}
POP_PORT=${POP_PORT:-110}
POPS_PORT=${POPS_PORT:-995}
REDIS_PORT=127.0.0.1:26379
SQL_PORT=127.0.0.1:25432
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

ensure_env_key() {
  key="$1"
  value="$2"
  if ! grep -q "^${key}=" "$state/.env"; then
    printf '%s=%s\n' "$key" "$value" >> "$state/.env"
  fi
}

ensure_env_key DBHOST "${DBHOST:-pgsql-billionmail}"
ensure_env_key DBPORT "${DBPORT:-5432}"
ensure_env_key DB_SSLMODE "${DB_SSLMODE:-disable}"
ensure_env_key DB_POOL_MODE "${DB_POOL_MODE:-session}"
ensure_env_key DB_MAX_CLIENT_CONN "${DB_MAX_CLIENT_CONN:-200}"
ensure_env_key DB_DEFAULT_POOL_SIZE "${DB_DEFAULT_POOL_SIZE:-20}"
ensure_env_key REDISHOST "${REDISHOST:-redis-billionmail}"
ensure_env_key REDISPORT "${REDISPORT:-6379}"
ensure_env_key REDIS_TLS "${REDIS_TLS:-false}"
ensure_env_key REDIS_TLS_VERIFY "${REDIS_TLS_VERIFY:-required}"
ensure_env_key REDIS_TLS_SERVER_NAME "${REDIS_TLS_SERVER_NAME:-}"
ensure_env_key REDISDB "${REDISDB:-1}"

printf '%s\n' "$version" > "$marker"
echo "BillionMail initialization completed"
