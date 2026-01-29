# Zendesk Data Collector

A Rails 8 application that extracts ticket data from Zendesk in real-time to a PostgreSQL database. The application uses JSONB for flexible schema support to handle dynamically created custom fields while maintaining indexed columns for common fields to optimize query performance.

## Features

- **Real-time Data Synchronization**: Continuously syncs ticket data from Zendesk using the Incremental Export API
- **Flexible Schema**: Stores complete ticket data in JSONB columns with indexed common fields for fast queries
- **Multi-tenant Support**: Manage multiple Zendesk accounts (domains) from a single installation
- **Background Job Processing**: Uses Solid Queue (Rails 8 default) for reliable background job processing
- **Automatic Comment Fetching**: Fetches and stores ticket comments separately with rate limiting protection
- **Rate Limit Handling**: Built-in rate limit detection and backoff to prevent API throttling
- **Admin Interface**: Powered by Avo 3.0 for managing Zendesk accounts and viewing ticket data
- **Job Monitoring**: Mission Control interface for monitoring background jobs and recurring tasks
- **Secure Credentials**: Encrypted API token storage using Rails Active Record Encryption

## Technology Stack

- **Framework**: Ruby on Rails 8.0
- **Ruby Version**: 3.2.4
- **Database**: PostgreSQL (stores tickets, admin users, desk configurations, and job queue)
- **Background Jobs**: Solid Queue (with recurring job support)
- **Admin Interface**: Avo 3.0
- **Authentication**: Devise
- **API Client**: zendesk_api gem
- **Deployment**: Docker & Docker Compose

## How It Works

1. **Configure Zendesk Accounts**: Add your Zendesk accounts (called "Desks") through the admin interface at `/avo`
2. **Automatic Data Collection**: Every second, the system checks for active desks ready for sync
3. **Incremental Export**: Uses Zendesk's Incremental Export API to fetch new and updated tickets since the last sync
4. **User Enrichment**: Sideloads user data from the API to enrich tickets with requester and assignee information
5. **Comment Collection**: Separately fetches comments for each ticket with rate limiting protection
6. **Data Storage**: Stores tickets in PostgreSQL with common fields in indexed columns and complete data in JSONB
7. **Multi-tenant**: Each desk can be synced independently with its own last sync timestamp

## Data Architecture

### Database Schema

The application uses PostgreSQL exclusively for all data storage:

- **zendesk_tickets**: Stores all ticket data with indexed columns for common fields (status, priority, assignee, etc.) and a JSONB column (`raw_data`) containing the complete API response including custom fields
- **desks**: Stores Zendesk account configurations (domain, encrypted API token, last sync timestamps)
- **admin_users**: Stores admin user accounts for accessing the admin interface (Devise authentication)
- **solid_queue_***: Tables for Solid Queue background job processing

### Ticket Data Storage

Common fields are extracted to indexed columns for performance:
- Core fields: `zendesk_id`, `domain`, `subject`, `status`, `priority`, `ticket_type`
- Requester info: `req_name`, `req_email`, `req_id`, `req_external_id`
- Assignment: `assignee_name`, `assignee_id`, `group_name`, `group_id`
- Timestamps: `created_at`, `updated_at`, `assigned_at`, `solved_at`
- Metrics: SLA metrics, wait times, resolution times
- Complete data: `raw_data` JSONB column with full API response

This hybrid approach provides:
- **Fast queries** on common fields using indexes
- **Flexibility** to access any field from the API response via JSONB
- **Forward compatibility** with new Zendesk fields without schema changes

## Background Job Architecture

The application uses three main jobs:

1. **QueueIncrementalTicketsJob** (recurring every second)
   - Finds desks ready for sync based on last sync time and wait intervals
   - Resets stuck "queued" flags for desks that have been processing too long
   - Queues IncrementalTicketJob for each ready desk

2. **IncrementalTicketJob** (high priority)
   - Fetches tickets from Zendesk Incremental Export API
   - Enriches tickets with sideloaded user data
   - Creates or updates tickets in PostgreSQL
   - Queues FetchTicketCommentsJob for each ticket with staggered delays
   - Updates desk's last sync timestamp

3. **FetchTicketCommentsJob** (lower priority, queued: comments)
   - Fetches comments for individual tickets
   - Implements rate limit detection and backoff
   - Stores comments in ticket's `raw_data` JSONB column

### Job Priority System

Jobs are prioritized to ensure efficient processing:
- **Priority 0**: Incremental ticket jobs (highest - process tickets first)
- **Priority 20**: Comment fetch jobs (lower - fetch comments after tickets)

## Admin Interface

Access the admin interface at `/avo` after logging in with your admin credentials.

### Features:
- **Desks Management**: Add, edit, and activate Zendesk accounts
- **Ticket Viewing**: Search and view synchronized ticket data
- **Job Monitoring**: View job status at `/jobs` (Mission Control)

### Initial Setup:
1. Login at `/avo` with the admin credentials configured during deployment
2. Navigate to "Desks" and click "New Desk"
3. Enter your Zendesk domain (e.g., `yourcompany.zendesk.com`), username/email, and API token
4. Set the desk to "Active" to start syncing
5. Monitor sync progress in the Desks list or check Jobs at `/jobs`

## Deployment

This application is deployed using Docker and Docker Compose. See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed deployment instructions covering:
- Coolify deployment with internal PostgreSQL
- Local development setup with Docker Compose
- Environment configuration
- Admin user setup

**Note**: The DEPLOYMENT.md file mentions MongoDB options, but this is outdated documentation. The application only uses PostgreSQL. MongoDB support was planned but never implemented.

## Reporting & Analytics

Once deployed and syncing data, you can connect your reporting tool of choice directly to the PostgreSQL database:

- Connection details are available in your deployment environment variables (`DATABASE_URL`)
- Query the `zendesk_tickets` table for ticket data
- Use indexed columns for fast queries on common fields
- Use JSONB operators to query custom fields in the `raw_data` column

Examples:
```sql
-- Query tickets by status
SELECT * FROM zendesk_tickets WHERE status = 'open' AND domain = 'yourcompany.zendesk.com';

-- Query custom fields from JSONB
SELECT zendesk_id, raw_data->>'custom_field_12345' as custom_value 
FROM zendesk_tickets 
WHERE domain = 'yourcompany.zendesk.com';

-- Aggregate ticket metrics
SELECT status, COUNT(*), AVG(full_resolution_time_in_minutes) 
FROM zendesk_tickets 
WHERE domain = 'yourcompany.zendesk.com' 
GROUP BY status;
```

## Development

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

Note: There is no `docker-compose.local.yml` file in the repository yet. For local development, use the `-coolify.yml` file with appropriate environment variables.

### Running Tests

The application uses Minitest (Rails default):

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/zendesk_ticket_test.rb

# Run with coverage
COVERAGE=true rails test
```

### Code Style

The project uses Standard Ruby for code style:

```bash
# Check style
bundle exec standardrb

# Auto-fix style issues
bundle exec standardrb --fix
```

## Security

- **API Tokens**: Encrypted using Rails Active Record Encryption (requires encryption keys in environment)
- **Authentication**: Devise-based authentication for admin access
- **Rate Limiting**: Rack::Attack for request rate limiting
- **Secure Credentials**: Environment-based configuration (no secrets in code)

## License

[Add license information here]
