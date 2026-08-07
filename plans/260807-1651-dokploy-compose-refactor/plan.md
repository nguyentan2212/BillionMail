# Dokploy Compose Refactor

Status: complete

## Outcome

Make the Dokploy deployment easier to maintain while preserving external PostgreSQL/Redis, persistent mail state, service names, network behavior, and mail TLS. Fix the reproducible Core image build failure caused by compiling two `main` functions.

## Constraints and Non-goals

- Keep existing bind-mounted state under `../files/billionmail`.
- Keep service names used by Core's Docker API integration.
- Do not redesign database, Redis, mail routing, or multi-IP behavior.
- Do not require host-side scripts outside the repository and Dokploy Compose workflow.

## Phases

1. Prove the build failure and identify duplicated or derived Compose state.
2. Fix the Core build entry point and centralize repeated environment mappings.
3. Remove unnecessary local image tags and the privileged certificate reloader service.
4. Validate rendered Compose, Docker builds, shell syntax, and focused Go tests.

## Acceptance Criteria

- [x] `docker compose --env-file dokploy.env.example -f docker-compose.dokploy.yml config --quiet` exits successfully.
- [x] The Core Docker image builds without the `main redeclared` error.
- [x] Persistent state paths and Dokploy routing remain compatible.
- [x] SMTP, submission, IMAP, and POP host ports remain configurable.
- [x] Certificate changes reload Postfix and Dovecot without a Docker-socket reloader container.
