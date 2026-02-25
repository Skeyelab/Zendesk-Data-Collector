# Zendesk Data Collector

Ruby on Rails 8 app that syncs Zendesk ticket data into PostgreSQL. Admin UI via Avo 3.0 at `/avo`, job monitoring at `/jobs`.

## Cursor Cloud specific instructions

### Services

| Service | How to run | Notes |
|---|---|---|
| PostgreSQL 16 | `sudo pg_ctlcluster 16 main start` | Must be running before Rails |
| Rails Web (Puma) | `bundle exec rails server -b 0.0.0.0 -p 3000` | Dev server on port 3000 |
| Solid Queue Worker | `bundle exec bin/jobs start` | Background job processor (optional for basic UI testing) |

### Key commands

See `README.md` for full details. Quick reference:

- **Lint**: `bundle exec standardrb` (auto-fix: `bundle exec standardrb --fix`)
- **Tests**: `bundle exec rails test`
- **DB setup**: `bundle exec rails db:create db:schema:load db:seed`
- **Dev server with worker**: `bundle exec foreman start -f Procfile` (starts both web + worker)

### Environment

- A `.env` file (gitignored) must exist in the project root with `SECRET_KEY_BASE`, `ACTIVE_RECORD_ENCRYPTION_*` keys, and optionally `DEFAULT_ADMIN_USER`/`DEFAULT_ADMIN_PW`. See `README.md` "Environment Variables for Local Development" for the template.
- The database config (`config/database.yml`) uses the current OS user by default when `DATABASE_URL` is not set — no password needed with PostgreSQL peer/trust auth.
- Test database is auto-derived from dev config; no separate `TEST_DATABASE_URL` is needed.

### Gotchas

- `ActiveRecord::Schema[8.1]` in `db/schema.rb` requires Rails 8.1 — `bundle exec rails db:schema:load` (not `db:migrate`) is the fastest way to set up a fresh database.
- The Gemfile pins `bundler 4.0.6`; the installed version must satisfy this.
- Solid Queue tables live in the same PostgreSQL database — no Redis needed.
- The deprecation warning about `config.active_support.to_time_preserves_timezone` in test output is harmless (from `config/initializers/new_framework_defaults.rb`).
