# Copilot Instructions for Zendesk Data Collector

## Project Overview

This is a Rails 8 application that extracts ticket data from Zendesk in real-time to a PostgreSQL database. The application uses JSONB for flexible schema support to handle dynamically created custom fields.

## Technology Stack

- **Framework**: Ruby on Rails 8.0
- **Ruby Version**: 3.2.4
- **Database**: PostgreSQL (with JSONB for dynamic fields)
- **Background Jobs**: Solid Queue
- **Admin Interface**: Avo 3.0
- **Authentication**: Devise
- **API Client**: zendesk_api gem
- **Testing**: Minitest (via Rails test suite)
- **Code Style**: Standard Ruby
- **Deployment**: Docker & Docker Compose (Coolify)

## Architecture & Key Concepts

### Data Model

- **ZendeskTicket**: Main model storing ticket data
  - Common fields are stored as indexed columns for fast queries
  - Complete API response stored in `raw_data` JSONB column
  - Uses `method_missing` to access custom fields from `raw_data`
  - Upserts based on `zendesk_id` + `domain` composite key
  - Supports multiple Zendesk domains (multi-tenant)

- **Desk**: Represents a Zendesk account configuration
  - Stores encrypted API token
  - Tracks last sync timestamp
  - Uses scopes like `readyToGo` for job scheduling
  - Has queued flag protection against concurrent jobs

- **AdminUser**: Devise-based authentication for admin access

### Background Job Architecture

- **QueueIncrementalTicketsJob**: Finds desks ready for sync and queues jobs
- **IncrementalTicketJob**: Fetches tickets from Zendesk API and saves to database
  - Uses Zendesk incremental export API with `start_time` parameter
  - Sideloads user data for enrichment
  - Handles upserts (create or update existing tickets)
  - Resets queued flag in `ensure` block

### Services

- **ZendeskClientService**: Handles Zendesk API authentication and connection

## Code Conventions

### Testing

- Use Minitest (Rails default testing framework)
- Test files located in `test/` directory (models, controllers, jobs, integration)
- Follow existing test patterns:
  - Use `setup` method for common test data
  - Use descriptive test names: `test "should do something"`
  - Use assertions like `assert`, `assert_equal`, `assert_not`, `assert_includes`
  - Mock external API calls with WebMock

### Code Style

- Follow Standard Ruby style guide (enforced by `standard` gem)
- Run `bundle exec standardrb` to check style
- Run `bundle exec standardrb --fix` to auto-fix style issues

### Models

- Use Rails validations for data integrity
- Define scopes for common queries
- Use `after_initialize` for default values
- Encrypt sensitive data (e.g., API tokens) with Rails encryption

### Jobs

- Inherit from `ApplicationJob`
- Use `queue_as :default`
- Include comprehensive logging with timestamps
- Always clean up state (e.g., reset flags) in `ensure` blocks
- Handle errors gracefully and continue processing when appropriate

### Logging

- Log important events with context (desk ID, domain, counts)
- Use both `Rails.logger` and `puts` for visibility in console and logs
- Include timestamps and progress indicators
- Log errors with class, message, and backtrace

## Development Workflow

### Local Setup

The repository includes two Docker Compose configurations:
- **`docker-compose.yml`**: Production deployment with internal PostgreSQL
- **`docker-compose-coolify.yml`**: Coolify-optimized deployment with Coolify magic variables

For local development, use `docker-compose.yml` with appropriate environment variables set in a `.env` file.

```bash
# Start all services (PostgreSQL, Rails, worker)
docker-compose up

# Run migrations (in another terminal)
docker-compose run web rails db:migrate

# Run tests
docker-compose run web rails test

# Run console
docker-compose run web rails console

# Check code style
docker-compose run web bundle exec standardrb

# Fix code style automatically
docker-compose run web bundle exec standardrb --fix
```

**Important**: The compose files are configured for production. For true local development, override environment variables:
- Set `RAILS_ENV=development`
- Mount code volumes for hot-reload: `-v $(pwd):/app`
- Use Procfile.local with foreman: `foreman start -f Procfile.local`

### Running Tests

The application uses **Minitest** (Rails 8 default) for testing. Tests are located in `test/` directory.

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/zendesk_ticket_test.rb

# Run specific test by line number
rails test test/models/zendesk_ticket_test.rb:15

# Run tests with coverage
COVERAGE=true rails test
```

**Test Setup Requirements:**
- PostgreSQL database connection for test environment
- WebMock for mocking external Zendesk API calls
- SimpleCov for coverage reporting (configured in test_helper.rb)

**Note**: Gemfile includes `rspec-rails` but all tests use Minitest. The gem may be a leftover dependency.

### Database Migrations

- Always test migrations with both up and down
- Use appropriate column types (JSONB for dynamic data, encrypted strings for tokens)
- Add indexes for frequently queried columns
- Use `change` method when possible for reversibility

## Key Files & Directories

- `app/models/` - ActiveRecord models (Desk, ZendeskTicket, AdminUser)
- `app/jobs/` - Background job classes (Solid Queue)
  - `incremental_ticket_job.rb` - Main ticket sync job
  - `fetch_ticket_comments_job.rb` - Fetches comments for tickets
  - `fetch_ticket_metrics_job.rb` - Fetches metrics for tickets
  - `queue_incremental_tickets_job.rb` - Recurring job that schedules ticket syncs
  - `zendesk_proxy_job.rb` - Proxies webhook requests to Zendesk API
  - `concerns/zendesk_api_headers.rb` - Shared rate limit handling
- `app/services/` - Service objects (e.g., ZendeskClientService, ZendeskTicketUpsertService)
- `app/avo/` - Avo admin interface resources and dashboards
- `app/controllers/webhooks/` - Webhook endpoints (e.g., tickets_controller.rb)
- `config/routes.rb` - Routes configuration (Devise, Avo, Mission Control, webhooks)
- `config/initializers/` - Rails initializers
  - `avo.rb` - Avo configuration
  - `rack_attack.rb` - Rate limiting configuration
  - `solid_queue.rb` - Background job queue configuration
- `test/` - Test suite using Minitest
  - `test/models/` - Model tests
  - `test/controllers/` - Controller tests
  - `test/jobs/` - Background job tests
  - `test/services/` - Service object tests
  - `test/integration/` - Integration tests
  - `test/fixtures/` - Test data fixtures
  - `test_helper.rb` - Test configuration and setup
- `db/migrate/` - Database migrations
- `db/seeds.rb` - Database seeding (creates default admin user)
- `.github/workflows/ci.yml` - GitHub Actions CI workflow
- `docker-compose.yml` - Production deployment with internal PostgreSQL
- `docker-compose-coolify.yml` - Coolify deployment configuration
- `Procfile` - Process definitions for production (Puma server, Solid Queue worker)
- `Procfile.local` - Process definitions for local development
- `Dockerfile` - Multi-stage Docker build (development and production targets)

## Important Patterns

### Ticket Data Processing

1. Fetch tickets from Zendesk API with sideloaded users
2. Enrich tickets with user data
3. Use `assign_ticket_data` method to map fields
4. Save or update using `find_or_initialize_by` for upserts
5. Store complete raw data in JSONB column

### Dynamic Field Access

- Common fields: Direct column access (`ticket.subject`)
- Custom fields: Access via `raw_data` hash (`ticket.raw_data["custom_field_123"]`)
- Method missing: Custom fields can also be accessed as methods if Rails doesn't have a column

### Error Handling

- Catch exceptions at job level to prevent worker crashes
- Log detailed error information
- Continue processing remaining items when one fails
- Always clean up resources in `ensure` blocks

## Deployment

The application supports two deployment configurations:
- **docker-compose.yml**: Production deployment with internal PostgreSQL
- **docker-compose-coolify.yml**: Coolify-optimized deployment with Coolify magic variables

See `DEPLOYMENT.md` for detailed deployment instructions.

## CI/CD Workflow

The repository uses GitHub Actions for continuous integration defined in `.github/workflows/ci.yml`.

### CI Pipeline Steps:

1. **Setup Services**: Starts PostgreSQL container
2. **Install Dependencies**: Installs Ruby 3.2.4 and runs `bundle install` (cached)
3. **System Dependencies**: Installs libpq-dev and build-essential
4. **Database Setup**: Creates test database and loads schema with `rails db:create db:schema:load`
5. **Run Tests**: Executes `bundle exec rails test`
6. **Upload Coverage**: Uploads SimpleCov coverage reports as artifacts

### Required Environment Variables for CI:
- `RAILS_ENV=test`
- `DATABASE_URL` - PostgreSQL connection string
- `SECRET_KEY_BASE` - Rails secret key
- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` - Encryption key (test value in CI)
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` - Deterministic encryption key (test value in CI)
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` - Key derivation salt (test value in CI)

### Testing Before Commit:

**Always run these commands before committing:**
```bash
# 1. Run code style checker
bundle exec standardrb

# 2. Fix style issues automatically
bundle exec standardrb --fix

# 3. Run all tests
bundle exec rails test

# 4. Verify database migrations work both ways
bundle exec rails db:migrate
bundle exec rails db:rollback
bundle exec rails db:migrate
```

**CI will fail if:**
- Code style violations exist (standardrb)
- Any tests fail
- Database migrations fail
- System dependencies are missing

## Admin Interface

- Powered by Avo 3.0
- Access at `/avo` (requires authentication)
- Manage Desks (Zendesk accounts) and view tickets
- Mission Control for job monitoring at `/jobs`

## Security Considerations

- API tokens are encrypted using Rails encryption
- Devise handles authentication for admin users
- Environment variables for sensitive configuration
- Use encrypted credentials in production

## When Making Changes

1. **Adding Fields**: If adding new Zendesk fields, update `assign_ticket_data` in `ZendeskTicket` model
2. **Changing Jobs**: Always test with actual Zendesk data when possible
3. **Database Changes**: Create migrations and test both up/down paths
4. **API Changes**: Update service objects and add appropriate error handling
5. **Admin Changes**: Update Avo resource files in `app/avo/`
6. **Tests**: Add tests for new functionality following existing patterns
7. **Style**: Run `standardrb` before committing

## Additional Notes

- The application is designed to handle multiple Zendesk accounts (domains)
- Background jobs use Solid Queue (Rails 8 default)
- All ticket data is preserved in raw_data JSONB for future flexibility
- The system prevents duplicate job execution using the `queued` flag

## Common Issues & Troubleshooting

### Database Connection Issues
- **Problem**: `PG::ConnectionBad` or database connection errors
- **Solution**: Ensure PostgreSQL is running and `DATABASE_URL` is correctly set
  ```bash
  # Check if PostgreSQL is running
  docker-compose ps postgres
  
  # Verify DATABASE_URL format
  # Should be: postgresql://user:password@host:port/database
  ```

### Rate Limiting Issues
- **Problem**: Zendesk API returns 429 (Too Many Requests)
- **Solution**: The application handles this automatically. Check:
  - `wait_till` timestamp on Desk model (should auto-update)
  - `ZENDESK_RATE_LIMIT_HEADROOM_PERCENT` environment variable (default: 18)
  - Job logs for retry attempts

### Test Failures
- **Problem**: Tests fail locally but CI passes (or vice versa)
- **Common Causes**:
  - Missing test environment variables (see `test_helper.rb`)
  - Database not cleaned between tests
  - WebMock not properly stubbing Zendesk API calls
  - Fixtures not loaded correctly
- **Solution**: 
  ```bash
  # Reset test database
  RAILS_ENV=test rails db:drop db:create db:schema:load
  
  # Run tests with verbose output
  rails test -v
  ```

### Background Jobs Not Running
- **Problem**: Jobs queued but not processing
- **Solution**: Ensure Solid Queue worker is running
  ```bash
  # Check worker status
  docker-compose ps worker
  
  # View worker logs
  docker-compose logs -f worker
  
  # Restart worker
  docker-compose restart worker
  ```

### Encryption Key Errors
- **Problem**: `ActiveRecord::Encryption::Errors::Configuration` or encryption errors
- **Solution**: Ensure all three encryption environment variables are set:
  ```bash
  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=<64 hex chars>
  ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=<64 hex chars>
  ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=<64 hex chars>
  
  # Generate keys with:
  ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"
  ```

### Docker Build Issues
- **Problem**: Docker build fails or is slow
- **Solution**: 
  ```bash
  # Clear Docker cache
  docker-compose build --no-cache
  
  # Remove old images
  docker system prune -a
  ```

### Code Style Violations
- **Problem**: CI fails due to standardrb violations
- **Solution**: Always run standardrb before committing
  ```bash
  # Check style
  bundle exec standardrb
  
  # Auto-fix most issues
  bundle exec standardrb --fix
  ```

## Environment Variables Reference

### Required for Production:
- `SECRET_KEY_BASE` - Rails secret key (auto-generated in Coolify via `SERVICE_PASSWORD_WEB`)
- `DATABASE_URL` - PostgreSQL connection string
- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` - 64-character hex string (32 bytes)
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` - 64-character hex string (32 bytes)
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` - 64-character hex string (32 bytes)

### Optional Configuration:
- `DEFAULT_ADMIN_USER` - Email for initial admin user (default: admin@example.com)
- `DEFAULT_ADMIN_PW` - Password for initial admin user (uses `SERVICE_PASSWORD_ADMIN` in Coolify)
- `WEBHOOKS_TICKETS_SECRET` - Webhook authentication secret (required for n8n integration)
- `RAILS_MAX_THREADS` - Puma thread count (default: 5)
- `SOLID_QUEUE_CONCURRENCY` - Background job workers (default: 5 production, 1 development)
- `ZENDESK_RATE_LIMIT_HEADROOM_PERCENT` - Rate limit headroom percentage (default: 18)
- `COMMENT_JOB_DELAY_SECONDS` - Initial delay for comment jobs (default: 0)
- `COMMENT_JOB_STAGGER_SECONDS` - Stagger between comment jobs (default: 0.2)
- `METRICS_JOB_DELAY_SECONDS` - Initial delay for metrics jobs (default: 0)
- `METRICS_JOB_STAGGER_SECONDS` - Stagger between metrics jobs (default: 0.2)
