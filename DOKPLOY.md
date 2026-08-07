# BillionMail on Dokploy with external PostgreSQL and Redis

This fork deploys BillionMail with one Docker Compose file while keeping all
persistent mail/configuration data under `../files/billionmail`.

The Dokploy stack intentionally does **not** include:

- PostgreSQL
- Redis
- PgBouncer
- a Redis TCP gateway
- Docker Compose profiles for local databases

Core, Postfix, Dovecot and Roundcube connect directly to the configured external
PostgreSQL server. Core and Rspamd connect directly to the configured external
Redis server.

## 1. Dokploy service

Create a Docker Compose service with:

```text
Repository:    nguyentan2212/BillionMail
Branch:        dev
Compose path:  docker-compose.dokploy.yml
Mode:          Docker Compose
Isolated deployments: OFF
```

The deployment builds the Core, Postfix, Dovecot and Rspamd adapters plus the
small initialization and certificate-sync images. Dokploy's normal deployment
supports this. A custom deployment command must be equivalent to:

```bash
docker compose \
  -f docker-compose.dokploy.yml \
  up -d \
  --build \
  --remove-orphans
```

Use **Clear Build Cache and Deploy** after changing a Dokploy Dockerfile,
entrypoint, or certificate hook.

## 2. External PostgreSQL

Create an empty PostgreSQL database and role before the first deployment. The
role must be able to create and alter tables, indexes and sequences in the
selected database/schema.

Example Dokploy environment:

```env
DBHOST=postgres.internal.example.com
DBPORT=5432
DBNAME=billionmail
DBUSER=billionmail
DBPASS=<strong URL-safe password>
DB_SSLMODE=disable
```

Use `DB_SSLMODE=require`, `verify-ca`, or `verify-full` when the external service
supports the corresponding TLS mode. For a private Docker network or trusted
private LAN, `disable` may be appropriate.

`DBHOST` must be a hostname or IP reachable from the BillionMail containers. Do
not use `127.0.0.1` unless PostgreSQL actually runs inside the same container,
which it does not in this deployment.

When PostgreSQL is another Dokploy service on the same VPS, either:

1. attach both services to a shared external Docker network and use the
   PostgreSQL service/network alias as `DBHOST`, or
2. use a private host address and a port exposed only to the private network.

## 3. External Redis

Example Dokploy environment:

```env
REDISHOST=redis.internal.example.com
REDISPORT=6379
REDISUSER=
REDISPASS=<strong password>
REDISDB=1
RSPAMD_REDISDB=0
REDIS_TLS=false
REDIS_TLS_VERIFY=required
REDIS_TLS_SERVER_NAME=
```

Core uses `REDISDB`, while Rspamd normally uses database `0`. The external Redis
instance must therefore support the selected logical databases. If the service
supports only database `0`, set both values to `0`.

Core supports an optional Redis ACL username through `REDISUSER`. Leaving it
empty uses password-only authentication/default user.

### Redis TLS limitation

The simplified Rspamd integration connects directly to Redis without a TLS
proxy. Therefore the shared Redis endpoint currently requires:

```env
REDIS_TLS=false
```

Use a private Docker network, private VLAN/VPC, Tailscale, WireGuard, or another
trusted private path. If the provider offers only TLS Redis, add a dedicated TLS
tunnel for Rspamd or restore a proxy; the external-only Compose intentionally
omits that extra layer.

## 4. Complete minimum environment

Start from `dokploy.env.example`. The important values are:

```env
BILLIONMAIL_CONFIG_VERSION=v4.9
BILLIONMAIL_CORE_VERSION=4.9.3
BILLIONMAIL_CONFIG_SYNC=missing
BILLIONMAIL_ENV_RECREATE=false

BILLIONMAIL_HOSTNAME=mail.example.com
ADMIN_USERNAME=mia-mail-admin
ADMIN_PASSWORD=<strong password>
SafePath=<random path>

DBHOST=<external PostgreSQL host>
DBPORT=5432
DBNAME=billionmail
DBUSER=billionmail
DBPASS=<external PostgreSQL password>
DB_SSLMODE=disable

REDISHOST=<external Redis host>
REDISPORT=6379
REDISUSER=
REDISPASS=<external Redis password>
REDISDB=1
RSPAMD_REDISDB=0
REDIS_TLS=false

HTTP_PORT=8080
HTTPS_PORT=8443
TZ=Asia/Ho_Chi_Minh
IPV4_NETWORK=10.89.0
```

Generate secrets with:

```bash
openssl rand -hex 24
openssl rand -hex 32
```

## 5. Domain

In the Dokploy Compose Domains tab:

```text
Domain:          mail.example.com
Service:         core-billionmail
Container port:  8080
Path:            /
Strip path:      OFF
HTTPS:           enabled
```

The management entry URL is:

```text
https://mail.example.com/<SafePath>
```

BillionMail intentionally redirects that one-time entry URL back to `/` after
saving the SafePath session.

Set BillionMail's Reverse Proxy Domain to:

```text
https://mail.example.com
```

The Compose file publishes SMTP (`25`, `465`, `587`), IMAP (`143`, `993`) and
POP (`110`, `995`) using the matching environment variables. Allow the selected
ports through the VPS and provider firewalls; Dokploy's HTTP domain only routes
the Core web service.

## 6. Persistent state

Persistent state remains under:

```text
../files/billionmail
```

This includes configuration, certificates, logs, mailboxes, the Postfix queue,
Roundcube files and Core state. PostgreSQL and Redis data are managed by the
external services and are no longer stored by this Compose project.

The initializer preserves `ADMIN_USERNAME`, `ADMIN_PASSWORD`, `SafePath` and
`BILLIONMAIL_HOSTNAME` after the first deployment. Infrastructure connection
settings (`DB*` and `REDIS*`) are synchronized from Dokploy on every deployment.
To intentionally rebuild the entire persistent `.env`, set:

```env
BILLIONMAIL_ENV_RECREATE=true
```

for one deployment, then return it to `false`.

## 7. Migrating an existing installation

Changing the Compose file does not copy data from the old local PostgreSQL. Use
`pg_dump`/`pg_restore` before removing the old database when the installation
already has domains, mailboxes, contacts, templates or campaigns.

Redis is mostly runtime/session/statistics state. Starting with an empty external
Redis is usually acceptable, but active sessions, rate-limit state and Rspamd
learning/statistics may be lost.

After the external services and new containers are confirmed healthy, remove
obsolete containers left by older deployments:

```bash
docker ps -aq \
  --filter label=com.docker.compose.service=pgsql-billionmail \
  --filter label=com.docker.compose.service=redis-billionmail \
  --filter label=com.docker.compose.service=pgsql-gateway \
  --filter label=com.docker.compose.service=redis-gateway
```

Because Docker applies multiple filters as AND in many commands, remove each
service separately when needed:

```bash
for service in \
  pgsql-billionmail \
  redis-billionmail \
  pgsql-gateway \
  redis-gateway \
  database-ready; do
  docker ps -aq \
    --filter "label=com.docker.compose.service=$service" |
  xargs -r docker rm -f
done
```

Do not delete the old bind-mount directories until PostgreSQL migration and
backups have been verified:

```text
../files/billionmail/postgresql-data
../files/billionmail/redis-data
../files/billionmail/postgresql-socket
```

## 8. Expected services

After a successful deployment, the long-running services are:

```text
rspamd-billionmail
dovecot-billionmail
postfix-billionmail
webmail-billionmail
core-billionmail
traefik-certs-dumper
```

`billionmail-init` exits with status `0`; that is expected.
`traefik-certs-dumper` watches Dokploy's Traefik certificate store. Postfix and
Dovecot reload themselves when the shared mail certificate changes, so no
Docker-socket certificate-reloader container is required.

There should be no running service named:

```text
pgsql-billionmail
redis-billionmail
pgsql-gateway
redis-gateway
database-ready
```

## 9. Update policy

Do not run `bm update` inside containers managed by Dokploy. Review upstream
changes, update the fork and redeploy with `--build --remove-orphans`. The custom
Core image compiles the fork's Go source so direct external PostgreSQL and Redis
support remains part of the deployed binary.
