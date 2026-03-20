# AGENTS.md

## Learned User Preferences

- Prefer concise, direct responses — no unnecessary affirmations or filler
- Prefer `yarn` over `npm` for JS package management
- TDD approach preferred; tests must pass before PRs
- Never commit directly to `main`; always suggest or create a feature branch
- Run `bin/standardrb --fix` before committing Ruby code
- Use `rvm` to ensure the correct Ruby version and gemset

## Learned Workspace Facts

- Production database is Neon project `zddc` (ID: `floral-tooth-23121188`), region `aws-us-east-2`; accessible via the `user-Neon` MCP
- App is deployed to Coolify (UUID `hwck40okg4c0kcksgowsg4w0`) at `https://zddc.noctua.ericdahl.dev`, project `markhardy` → production
- A companion repo at `~/Documents/GitHub/noctua` queries the same `zddc` Neon database using raw SQL (TypeScript, `pg` driver — no ORM)
- `docker-compose-coolify-external.yml` is the active production compose file (uses external Neon DB); `docker-compose-coolify.yml` is the internal-postgres variant
- `Desk#token` is encrypted via Active Record encryption; the three `ACTIVE_RECORD_ENCRYPTION_*` vars must be set directly in Coolify's env UI — they cannot be resolved via `${SERVICE_PASSWORD_*}` substitution at compose parse time
- Coolify renames services for PR preview deployments (e.g., `postgres` → `postgres-pr-101`), which breaks hardcoded hostnames in `DATABASE_URL` strings
- `SERVICE_PASSWORD_*` Coolify variables are injected directly into containers at runtime and are NOT available during Docker Compose variable substitution at parse time
- `zendesk_tickets` has a 1 GB GIN index on `raw_data` (zero scans, should be dropped); noctua queries all filter by `domain + status`, making a composite index on `(domain, status, created_at)` the high-value addition
- The webhook endpoint at `Webhooks::ZendeskController#create` requires `domain`, `resource`, and `method` fields; `ticket_id` is required for `get` and `put` methods
- `ZendeskProxyJob` handles 429 rate-limit responses automatically with retry logic up to `MAX_RETRIES`
