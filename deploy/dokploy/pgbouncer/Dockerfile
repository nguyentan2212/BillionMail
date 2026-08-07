FROM alpine:3.22

RUN apk add --no-cache \
      ca-certificates \
      pgbouncer \
      postgresql-client \
      su-exec \
    && if ! grep -q '^pgbouncer:' /etc/group; then addgroup -S pgbouncer; fi \
    && if ! id -u pgbouncer >/dev/null 2>&1; then adduser -S -D -H -G pgbouncer pgbouncer; fi \
    && mkdir -p /etc/pgbouncer /var/run/postgresql \
    && chown -R pgbouncer:pgbouncer /etc/pgbouncer /var/run/postgresql

COPY deploy/dokploy/pgbouncer/entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

EXPOSE 5432
ENTRYPOINT ["/entrypoint.sh"]
