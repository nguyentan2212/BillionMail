# BillionMail fork: one-deploy installation on Dokploy

This overlay replaces the earlier two-step `seed -> production` workflow with
one Docker Compose deployment.

## Why an initializer is still needed

BillionMail's upstream Compose mounts `./conf`, `./ssl`, `./postgresql-data`,
and other paths directly from the repository checkout. Dokploy performs a fresh
clone during deployments, so long-running bind mounts must not depend on that
checkout. The initializer embeds `conf/` and `ssl-self-signed/` in a small image,
then copies them to `../files/billionmail`. All long-running services mount only
persistent paths.

## 1. Create a stable fork branch

The upstream default branch is `dev`. Start the Dokploy branch from a stable
release tag instead:

```bash
git clone https://github.com/YOUR_ACCOUNT/BillionMail.git
cd BillionMail
git remote add upstream https://github.com/Billionmail/BillionMail.git
git fetch upstream --tags
git switch -c dokploy-v4.9 v4.9
```

Copy these overlay files into the fork root:

```text
docker-compose.dokploy.yml
dokploy.env.example
DOKPLOY.md
deploy/dokploy/Dockerfile.init
deploy/dokploy/init.sh
deploy/dokploy/pgbouncer/Dockerfile
deploy/dokploy/pgbouncer/entrypoint.sh
deploy/dokploy/redis-gateway/Dockerfile
deploy/dokploy/redis-gateway/entrypoint.sh
```

Commit and push:

```bash
git add docker-compose.dokploy.yml dokploy.env.example DOKPLOY.md deploy/dokploy
git commit -m "deploy: add single-deploy Dokploy setup"
git push -u origin dokploy-v4.9
```

## 2. Create the Dokploy Compose service

Use:

```text
Source:       GitHub fork
Branch:       dokploy-v4.9
Compose path: docker-compose.dokploy.yml
Mode:         Docker Compose (not Docker Stack)
Auto Deploy:  optional
Isolated Deployments: OFF
```

The deployment command must include `--build`, because the initializer,
PgBouncer gateway, and Redis gateway are built from the fork. Dokploy's normal
Compose deployment generally handles builds; if you use a custom command, use
the full command shown by Dokploy and add `--build --remove-orphans`.

Paste `dokploy.env.example` into Dokploy Environment and replace every secret.
Generate values with:

```bash
openssl rand -hex 24
openssl rand -hex 12
openssl rand -hex 32
```

## 3. Deploy once

During the same deployment:

1. Dokploy clones the fork.
2. Docker builds the initializer, PgBouncer gateway, and Redis gateway.
   The Core image defaults to `4.9.3`, matching the current upstream dev Compose
   and avoiding the `Scan(&int)` SMTP relay migration bug in `4.9.0`.
3. `billionmail-init` initializes `../files/billionmail` and exits successfully.
4. The PostgreSQL gateway connects to local or external PostgreSQL.
5. The Redis gateway connects to local or external Redis while preserving the
   internal endpoint `redis:6379` expected by Core and Rspamd.
6. Rspamd, Dovecot, Postfix, Roundcube and Core start after database and Redis
   health checks succeed.

An exited `billionmail-init` container with exit code 0 is expected.

## 4. Add the domain

In the Compose Domains tab:

```text
Domain:  mail.example.com
Service: core-billionmail
Port:    8080
HTTPS:   enabled
Path:    /
```

The management URL is:

```text
https://mail.example.com/<SafePath>
```

Set BillionMail's Reverse Proxy Domain to:

```text
https://mail.example.com
```

## 5. Persistent state

All state lives under:

```text
../files/billionmail
```

The repository itself contains no production secrets or mail data.

The initializer does not overwrite the persistent `.env` during ordinary
redeployments because BillionMail can edit that file from its Settings UI.
To intentionally regenerate it from Dokploy values, set:

```env
BILLIONMAIL_ENV_RECREATE=true
```

for one deployment, then immediately return it to `false`. This overwrites UI
changes to admin username, password, SafePath and hostname.

## 6. Updating BillionMail

Do not run `bm update` inside the managed containers. For a new upstream release:

```bash
git fetch upstream --tags
git switch -c dokploy-vNEXT vNEXT
git cherry-pick <commit-containing-the-Dokploy-overlay>
```

Then review:

```text
- upstream docker-compose.yml image tags
- additions/changes under conf/
- database migration notes
- Dockerfile/entrypoint changes
```

Update the image tags and `BILLIONMAIL_CONFIG_VERSION` in the Dokploy Compose,
then deploy the new branch. The default sync mode `missing` only adds newly
introduced files; it deliberately does not overwrite modified configuration.
Use `overwrite` only after a complete backup and manual diff review.

## 7. First-run warnings

The initializer explicitly creates the runtime-only directories:

```text
../files/billionmail/conf/askai
../files/billionmail/rspamd-data/dkim
```

This prevents repeated `conf/askai: no such file or directory` and initial DKIM
repair warnings on a fresh database.

The upstream Core image may still print `chown: unknown user/group root:crontab`
and early fail2ban reload warnings. The process continues and fail2ban is
subsequently started by Supervisor. Set `FAIL2BAN_INIT=n` if fail2ban is managed
at the VPS/Traefik layer and you do not want the in-container startup warnings.

## 8. Local or external PostgreSQL and Redis

The same Compose profile controls both bundled data services:

```env
COMPOSE_PROFILES=local-db
```

With that profile enabled, both `pgsql-billionmail` and `redis-billionmail` are
started. With it empty, both local services are disabled and the two gateways
connect to external servers.

### Bundled PostgreSQL and Redis

Keep these Dokploy environment values:

```env
COMPOSE_PROFILES=local-db

DBHOST=pgsql-billionmail
DBPORT=5432
DB_SSLMODE=disable

REDISHOST=redis-billionmail
REDISPORT=6379
REDISPASS=<password used by the bundled Redis>
REDISDB=1
REDIS_TLS=false
REDIS_TLS_VERIFY=required
REDIS_TLS_SERVER_NAME=
```

Persistent local data remains in:

```text
../files/billionmail/postgresql-data
../files/billionmail/redis-data
```

All BillionMail PostgreSQL clients connect to `pgsql:5432` through PgBouncer.
All BillionMail Redis clients connect to `redis:6379` through the Redis gateway.
This preserves the hard-coded hostnames used by the upstream Core and Rspamd
images.

### External PostgreSQL and Redis

Disable the local profile and point both gateways at reachable external hosts:

```env
COMPOSE_PROFILES=

DBHOST=postgres.example.internal
DBPORT=5432
DBNAME=billionmail
DBUSER=billionmail
DBPASS=<URL-safe password, preferably hex>
DB_SSLMODE=require
DB_POOL_MODE=session
DB_MAX_CLIENT_CONN=200
DB_DEFAULT_POOL_SIZE=20

REDISHOST=redis.example.internal
REDISPORT=6380
REDISPASS=<external Redis password>
REDISDB=1
REDIS_TLS=true
REDIS_TLS_VERIFY=required
REDIS_TLS_SERVER_NAME=redis.example.internal
```

For services on another Dokploy project, attach the projects to a shared external
Docker network or use a DNS/private IP address reachable from the BillionMail
network. `127.0.0.1` inside a container is the container itself, not the VPS host.

The external PostgreSQL role must be able to connect, create tables, indexes,
sequences, and alter the `public` schema used by BillionMail migrations. Create
an empty database before the first deployment.

The external Redis server must support password authentication using the default
Redis user. BillionMail currently supplies only a password, not a separate ACL
username. It also uses logical database `0` for Rspamd and `REDISDB` (default `1`)
for Core. If the provider supports only database `0`, set:

```env
REDISDB=0
```

Redis Cluster endpoints are not suitable because they normally reject `SELECT`
and do not provide the logical database behavior expected by BillionMail. Use a
standalone or primary endpoint instead.

`REDIS_TLS=true` makes the internal gateway establish TLS to the external Redis
server while BillionMail containers continue using plaintext on the private
Docker network. Keep `REDIS_TLS_VERIFY=required` for a publicly trusted
certificate. `REDIS_TLS_VERIFY=none` is available for a private/self-signed
endpoint but disables certificate verification.

Changing the profile does not migrate existing data. Move PostgreSQL with
`pg_dump`/`pg_restore` before changing `DBHOST`. Redis mostly contains runtime
cache, sessions, rate-limit data and Rspamd statistics, but switching to a fresh
external Redis can still reset those values. Export/import Redis separately when
that state must be retained.
