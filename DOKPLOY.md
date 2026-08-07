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

The deployment command must include `--build`, because the initializer is built
from the fork. Dokploy's normal Compose deployment generally handles builds; if
you use a custom command, use the full command shown by Dokploy and add
`--build --remove-orphans`.

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
2. Docker builds `local/billionmail-dokploy-init:v4.9` with the matching upstream
   configuration embedded in the image.
3. `billionmail-init` initializes `../files/billionmail` and exits successfully.
4. PostgreSQL, Redis, Rspamd, Dovecot, Postfix, Roundcube and Core start.

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
