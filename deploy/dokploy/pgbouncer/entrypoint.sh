#!/bin/sh
set -eu

: "${DBHOST:?DBHOST is required}"
: "${DBNAME:?DBNAME is required}"
: "${DBUSER:?DBUSER is required}"
: "${DBPASS:?DBPASS is required}"

DBPORT="${DBPORT:-5432}"
DB_SSLMODE="${DB_SSLMODE:-disable}"
DB_POOL_MODE="${DB_POOL_MODE:-session}"
DB_MAX_CLIENT_CONN="${DB_MAX_CLIENT_CONN:-200}"
DB_DEFAULT_POOL_SIZE="${DB_DEFAULT_POOL_SIZE:-20}"

case "$DBHOST" in
  *[!A-Za-z0-9_.:-]*)
    echo "DBHOST contains unsupported characters" >&2
    exit 2
    ;;
esac

case "$DBNAME" in
  ''|*[!A-Za-z0-9_]*)
    echo "DBNAME must contain only letters, numbers, and underscores" >&2
    exit 2
    ;;
esac

case "$DBUSER" in
  ''|*[!A-Za-z0-9_]*)
    echo "DBUSER must contain only letters, numbers, and underscores" >&2
    exit 2
    ;;
esac

case "$DBPASS" in
  *[!A-Za-z0-9._~-]*)
    echo "DBPASS must be URL-safe; a hex password is recommended" >&2
    exit 2
    ;;
esac

case "$DBPORT" in
  ''|*[!0-9]*)
    echo "DBPORT must be numeric" >&2
    exit 2
    ;;
esac

case "$DB_SSLMODE" in
  disable|prefer|require) ;;
  *)
    echo "Unsupported DB_SSLMODE: $DB_SSLMODE" >&2
    exit 2
    ;;
esac

case "$DB_POOL_MODE" in
  session|transaction|statement) ;;
  *)
    echo "Unsupported DB_POOL_MODE: $DB_POOL_MODE" >&2
    exit 2
    ;;
esac

case "$DB_MAX_CLIENT_CONN:$DB_DEFAULT_POOL_SIZE" in
  *[!0-9:]*)
    echo "DB_MAX_CLIENT_CONN and DB_DEFAULT_POOL_SIZE must be numeric" >&2
    exit 2
    ;;
esac

mkdir -p /etc/pgbouncer /var/run/postgresql
rm -f /var/run/postgresql/.s.PGSQL.5432 /var/run/postgresql/.s.PGSQL.5432.lock
chown -R pgbouncer:pgbouncer /etc/pgbouncer /var/run/postgresql
chmod 0777 /var/run/postgresql

cat > /etc/pgbouncer/userlist.txt <<EOF_USERS
"billionmail" "$DBPASS"
EOF_USERS

if [ "$DBUSER" != "billionmail" ]; then
  printf '"%s" "%s"\n' "$DBUSER" "$DBPASS" >> /etc/pgbouncer/userlist.txt
fi

cat > /etc/pgbouncer/databases.ini <<EOF_DATABASES
billionmail = host=$DBHOST port=$DBPORT dbname=$DBNAME user=$DBUSER password=$DBPASS
EOF_DATABASES

if [ "$DBNAME" != "billionmail" ]; then
  printf '%s = host=%s port=%s dbname=%s user=%s password=%s\n' \
    "$DBNAME" "$DBHOST" "$DBPORT" "$DBNAME" "$DBUSER" "$DBPASS" \
    >> /etc/pgbouncer/databases.ini
fi

{
  echo '[databases]'
  cat /etc/pgbouncer/databases.ini
  cat <<EOF_CONFIG

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 5432
unix_socket_dir = /var/run/postgresql
unix_socket_mode = 0777

auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = $DB_POOL_MODE
max_client_conn = $DB_MAX_CLIENT_CONN
default_pool_size = $DB_DEFAULT_POOL_SIZE
reserve_pool_size = 5
server_reset_query = DISCARD ALL
server_tls_sslmode = $DB_SSLMODE
ignore_startup_parameters = extra_float_digits,options
server_login_retry = 3
dns_max_ttl = 15

log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
logfile = /dev/stdout
pidfile = /tmp/pgbouncer.pid
EOF_CONFIG
} > /etc/pgbouncer/pgbouncer.ini

chmod 0600 /etc/pgbouncer/userlist.txt /etc/pgbouncer/databases.ini /etc/pgbouncer/pgbouncer.ini
chown pgbouncer:pgbouncer /etc/pgbouncer/userlist.txt /etc/pgbouncer/databases.ini /etc/pgbouncer/pgbouncer.ini

exec su-exec pgbouncer:pgbouncer pgbouncer /etc/pgbouncer/pgbouncer.ini
