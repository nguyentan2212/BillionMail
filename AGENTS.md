# Repository Guidelines

## Project Structure & Module Organization

`core/` contains the Go application: API contracts live in `core/api/`, HTTP controllers in `core/internal/controller/`, business logic in `core/internal/service/`, and persistence code in `core/internal/dao/`. The Vue 3/TypeScript client is under `core/frontend/src/`; keep views, reusable components, stores, and API clients in their existing feature directories. Mail-service configuration lives in `conf/`, container definitions in `Dockerfiles/`, deployment assets in `deploy/` and `core/manifest/`, and end-to-end tests in `e2e/`. Treat `core/public/dist/` and vendored files under `core/frontend/public/static/` as generated artifacts.

## Build, Test, and Development Commands

- `docker compose up -d` starts the complete local stack after configuration from `env_init`.
- `cd core && make build` builds the Go service through the GoFrame CLI.
- `cd core/frontend && pnpm install && pnpm dev` installs locked dependencies and starts the frontend dev server.
- `cd core/frontend && pnpm build` creates a production frontend bundle.
- `cd core && go test -count=1 -short ./internal/service/...` runs fast backend service tests without database integration.
- `cd core/frontend && pnpm test` runs Vitest once; use `pnpm test:coverage` for coverage.

## Coding Style & Naming Conventions

Format Go with `gofmt` and validate it with `go vet ./...`. Keep domain packages lowercase with underscores where established, and place tests beside their source. Frontend code follows ESLint and Prettier: tabs, two-column tab width, 100-character lines, single quotes, and no semicolons. Run `pnpm lint` and `pnpm format` from `core/frontend`. Follow existing Vue component and feature naming rather than introducing a parallel structure.

## Testing Guidelines

Name Go tests `*_test.go`; frontend tests must match `src/**/*.{test,spec}.{ts,tsx}`. Python E2E tests use pytest and the numbered `e2e/tests/test_*.py` pattern. Add focused regression tests with behavior changes. No numeric coverage minimum is configured; keep touched logic meaningfully exercised.

## Commit & Pull Request Guidelines

History uses Conventional Commits such as `fix: ...`, `feat: ...`, and `refactor: ...`. PR titles should use `<type>(<scope>): <present-tense description>`, stay under 76 characters, and omit ending punctuation. Start descriptions with `Fixes #123` or `Updates #123`, explain purpose and implementation, list validation, and include screenshots for UI changes. Per the PR template, target frontend work to `dev-frontend` and backend/core work to `main`; verify SPF/DKIM behavior when mail-sending logic changes.

## Security & Configuration

Never commit local environment overrides, credentials, private keys, or production data. Begin from `env_init`, document new settings there, and report vulnerabilities through the contact in `SECURITY.md` rather than a public issue.
