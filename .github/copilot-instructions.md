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

```bash
# Start all services (PostgreSQL, Rails, worker)
docker-compose -f docker-compose.local.yml up

# Run migrations
docker-compose -f docker-compose.local.yml run web rails db:migrate

# Run tests
docker-compose -f docker-compose.local.yml run web rails test

# Run console
docker-compose -f docker-compose.local.yml run web rails console

# Check code style
docker-compose -f docker-compose.local.yml run web bundle exec standardrb
```

### Running Tests

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/zendesk_ticket_test.rb

# Run specific test
rails test test/models/zendesk_ticket_test.rb:15
```

### Database Migrations

- Always test migrations with both up and down
- Use appropriate column types (JSONB for dynamic data, encrypted strings for tokens)
- Add indexes for frequently queried columns
- Use `change` method when possible for reversibility

## Key Files & Directories

- `app/models/` - ActiveRecord models (Desk, ZendeskTicket, AdminUser)
- `app/jobs/` - Background job classes (Solid Queue)
- `app/services/` - Service objects (e.g., ZendeskClientService)
- `app/avo/` - Avo admin interface resources
- `config/routes.rb` - Routes configuration (Devise, Avo, Mission Control)
- `test/` - Test suite (models, controllers, jobs, integration)
- `docker-compose*.yml` - Various Docker Compose configurations for different deployment scenarios

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

The application supports multiple deployment configurations:
- **docker-compose.yml**: Coolify with external databases
- **docker-compose-coolify.yml**: Coolify with internal PostgreSQL
- **docker-compose.local.yml**: Local development

See `DEPLOYMENT.md` for detailed deployment instructions.

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
