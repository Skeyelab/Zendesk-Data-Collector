# Zendesk Data Collector

A Rails 8 application that extracts ticket data from Zendesk in real-time to a PostgreSQL database. The application uses JSONB for flexible schema support to handle dynamically created custom fields while maintaining indexed columns for common fields to optimize query performance.

## Features

- **Real-time Data Synchronization**: Continuously syncs ticket data from Zendesk using the Incremental Export API
- **Flexible Schema**: Stores complete ticket data in JSONB columns with indexed common fields for fast queries
- **Multi-tenant Support**: Manage multiple Zendesk accounts (domains) from a single installation
- **Background Job Processing**: Uses Solid Queue (Rails 8 default) for reliable background job processing with priority queues
- **Configurable Data Collection**: Per-desk control over comment and metrics fetching
- **Automatic Comment Fetching**: Fetches and stores ticket comments separately with staggered delays and rate limiting protection
- **Automatic Metrics Extraction**: Fetches ticket metrics and extracts to indexed columns for fast reporting
- **Comprehensive Rate Limit Handling**: Built-in rate limit detection, backoff, retry logic, and persistent state management
- **n8n Webhook Proxy**: Queued proxy for n8n (or other callers) to forward Zendesk API calls (GET/PUT/POST tickets) through the same rate-limit queue—no ticket data is stored from the webhook
- **Admin Interface**: Powered by Avo 3.0 for managing Zendesk accounts and viewing ticket data with dashboard cards
- **Job Monitoring**: Mission Control interface for monitoring background jobs, recurring tasks, and queue health
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
   - Configure which data to fetch: enable/disable comments and metrics per desk
2. **Automatic Data Collection**: Every second, the system checks for active desks ready for sync
3. **Incremental Export**: Uses Zendesk's Incremental Export API to fetch new and updated tickets since the last sync
4. **User Enrichment**: Sideloads user data from the API to enrich tickets with requester and assignee information
5. **Comment Collection**: Separately fetches comments for each ticket with rate limiting protection (if enabled)
6. **Metrics Collection**: Separately fetches metrics for each ticket and extracts to indexed columns (if enabled)
7. **Data Storage**: Stores tickets in PostgreSQL with common fields in indexed columns and complete data in JSONB
8. **Multi-tenant**: Each desk can be synced independently with its own last sync timestamp and configuration

## Data Architecture

### Database Schema

The application uses PostgreSQL exclusively for all data storage:

- **zendesk_tickets**: Stores all ticket data with indexed columns for common fields (status, priority, assignee, etc.), metrics columns (resolution times, wait times, etc.), and a JSONB column (`raw_data`) containing the complete API response including custom fields, comments, and raw metrics
- **desks**: Stores Zendesk account configurations (domain, encrypted API token, last sync timestamps, `fetch_comments` and `fetch_metrics` flags)
- **admin_users**: Stores admin user accounts for accessing the admin interface (Devise authentication)
- **solid_queue_***: Tables for Solid Queue background job processing

### Ticket Data Storage

Common fields are extracted to indexed columns for performance:
- Core fields: `zendesk_id`, `domain`, `subject`, `status`, `priority`, `ticket_type`
- Requester info: `req_name`, `req_email`, `req_id`, `req_external_id`
- Assignment: `assignee_name`, `assignee_id`, `group_name`, `group_id`
- Timestamps: `created_at`, `updated_at`, `assigned_at`, `solved_at`
- Metrics: SLA metrics (first reply, first/full resolution times), wait times (agent, requester, on hold), counters (reopens, replies), business hours variants
- Comments: Stored as array in `raw_data["comments"]`
- Complete data: `raw_data` JSONB column with full API response, including custom fields and raw metrics

This hybrid approach provides:
- **Fast queries** on common fields using indexes
- **Flexibility** to access any field from the API response via JSONB
- **Forward compatibility** with new Zendesk fields without schema changes
- **Optimized metrics** extracted to columns for reporting and analytics

## Background Job Architecture

The application uses four main jobs:

1. **QueueIncrementalTicketsJob** (recurring every second)
   - Finds desks ready for sync based on last sync time and wait intervals
   - Resets stuck "queued" flags for desks that have been processing too long
   - Queues IncrementalTicketJob for each ready desk

2. **IncrementalTicketJob** (Priority 0 - high priority)
   - Fetches tickets from Zendesk Incremental Export API
   - Enriches tickets with sideloaded user data
   - Creates or updates tickets in PostgreSQL
   - Queues FetchTicketCommentsJob and FetchTicketMetricsJob for each ticket with staggered delays
   - Updates desk's last sync timestamp

3. **FetchTicketCommentsJob** (Priority 10 - lower priority, queues: `comments`, `comments_closed`)
   - Fetches comments for individual tickets from `/api/v2/tickets/{id}/comments.json`
   - Only queued when updating existing tickets (not for new tickets)
   - Uses staggered delays to prevent API rate limiting (configurable via `COMMENT_JOB_STAGGER_SECONDS`)
   - Implements rate limit detection and backoff with retry logic
   - Stores comments array in ticket's `raw_data["comments"]` JSONB column
   - Can be disabled per desk with `fetch_comments` flag

4. **FetchTicketMetricsJob** (Priority 10 - lower priority, queues: `metrics`, `metrics_closed`)
   - Fetches ticket metrics from `/api/v2/tickets/{id}/metrics.json`
   - Extracts metrics to indexed columns for fast queries:
     - Time metrics: `first_reply_time_in_minutes`, `first_resolution_time_in_minutes`, `full_resolution_time_in_minutes`
     - Wait times: `agent_wait_time_in_minutes`, `requester_wait_time_in_minutes`, `on_hold_time_in_minutes`
     - Counters: `reopens`, `replies`
     - Business hours variants for all time metrics
   - Also stores raw response in `raw_data["ticket_metric"]` JSONB column
   - Uses staggered delays to prevent API rate limiting (configurable via `METRICS_JOB_STAGGER_SECONDS`)
   - Implements rate limit detection and backoff with retry logic
   - Can be disabled per desk with `fetch_metrics` flag

4. **ZendeskProxyJob** (queued: proxy)
   - Proxies a single Zendesk API call (GET/PUT/POST tickets) from the webhook endpoint
   - Uses the same rate limit handling as other Zendesk jobs
   - Does **not** create or update `ZendeskTicket` rows—only forwards the request to Zendesk

### Job Priority System

Jobs are prioritized to ensure efficient processing:
- **Priority 0**: Incremental ticket jobs (highest - process tickets first)
- **Priority 10**: Comment and metrics fetch jobs (lower - fetch details after tickets)
- **proxy** queue: ZendeskProxyJob (webhook-proxied Zendesk API calls from n8n)

### Conditional Queue Names

To optimize processing of closed/solved tickets, the application uses different queues:
- Active tickets: Uses `comments` and `metrics` queues
- Closed/solved tickets: Uses `comments_closed` and `metrics_closed` queues

This allows you to prioritize processing of active tickets if needed by configuring different worker pools.

## n8n Webhook Proxy

The app exposes a **queued proxy** so tools like n8n can call the Zendesk API through your rate-limit queue without storing ticket data in this app.

- **Endpoint**: `POST /webhooks/tickets`
- **Authentication**: Required via `X-Webhook-Secret` header (see Configuration below)
- **Behavior**: Request is enqueued as `ZendeskProxyJob` on the **proxy** queue. The job performs the Zendesk API call using the same rate-limit logic (Desk `wait_till`, throttle, 429 retries). No `ZendeskTicket` rows are created or updated from the webhook.
- **Validation**: The webhook validates that the specified `domain` corresponds to an active Desk before enqueueing the job.
- **Rack::Attack**: This path is safelisted from throttling only for authenticated requests with the correct shared secret.

### Configuration

Set the `WEBHOOKS_TICKETS_SECRET` environment variable to a secure random string (e.g., generated with `openssl rand -hex 32`):

```bash
WEBHOOKS_TICKETS_SECRET=your_secure_random_string_here
```

All webhook requests must include this secret in the `X-Webhook-Secret` header. The comparison is done using secure cryptographic hashing to prevent timing attacks.

### Payload (JSON)

| Field       | Required | Description |
|------------|----------|-------------|
| `domain`   | Yes      | Zendesk subdomain (e.g. `yourcompany.zendesk.com`). Must match an active configured Desk. |
| `method`   | No       | `get`, `put`, or `post`. Default: `get`. |
| `ticket_id`| For get/put | Zendesk ticket ID. Required for `get` and `put`. |
| `body`     | For put/post | Request body for Zendesk API (e.g. `{ "ticket": { "status": "solved" } }`). |

### Examples

**GET a ticket** (proxy fetches from Zendesk, does not store):

```bash
curl -X POST https://your-app.com/webhooks/tickets \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: your_secure_random_string_here" \
  -d '{ "domain": "yourcompany.zendesk.com", "method": "get", "ticket_id": 12345 }'
```

**UPDATE a ticket** (proxy sends PUT to Zendesk):

```bash
curl -X POST https://your-app.com/webhooks/tickets \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: your_secure_random_string_here" \
  -d '{
    "domain": "yourcompany.zendesk.com",
    "method": "put",
    "ticket_id": 12345,
    "body": { "ticket": { "status": "solved" } }
  }'
```

**CREATE a ticket** (proxy sends POST to Zendesk):

```bash
curl -X POST https://your-app.com/webhooks/tickets \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: your_secure_random_string_here" \
  -d '{
    "domain": "yourcompany.zendesk.com",
    "method": "post",
    "body": {
      "ticket": {
        "subject": "New ticket",
        "comment": { "body": "Initial comment" }
      }
    }
  }'
```

Response: `202 Accepted` with `{ "status": "accepted" }`. The actual Zendesk call runs asynchronously on the proxy queue.

### Error Responses

- `401 Unauthorized`: Missing or invalid `X-Webhook-Secret` header
- `404 Not Found`: No active Desk found for the specified domain
- `422 Unprocessable Entity`: Invalid parameters (missing domain, invalid method, etc.)
- `500 Internal Server Error`: Webhook authentication not configured (`WEBHOOKS_TICKETS_SECRET` not set)

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
4. Configure data collection options:
   - Check "Fetch Comments" to enable comment fetching (enabled by default)
   - Check "Fetch Metrics" to enable metrics fetching (enabled by default)
5. Set the desk to "Active" to start syncing
6. Monitor sync progress in the Desks list or check Jobs at `/jobs`

## Configuration

### Desk Configuration Options

Each Zendesk account (Desk) can be configured with the following options via the Avo admin interface:

- **Active**: Enable/disable syncing for this desk
- **Fetch Comments**: When enabled, fetches comments for each ticket and stores in `raw_data["comments"]`
- **Fetch Metrics**: When enabled, fetches metrics for each ticket and extracts to indexed columns

### Environment Variables

The following environment variables can be used to configure the application:

**Rate Limiting & API Control:**
- `ZENDESK_RATE_LIMIT_HEADROOM_PERCENT` - Percentage of rate limit to maintain as headroom before backing off (default: `18`)
- `COMMENT_JOB_DELAY_SECONDS` - Initial delay before processing comment jobs (default: `0`)
- `COMMENT_JOB_STAGGER_SECONDS` - Delay between each comment job to prevent API flooding (default: `0.2`)
- `METRICS_JOB_DELAY_SECONDS` - Initial delay before processing metrics jobs (default: `0`)
- `METRICS_JOB_STAGGER_SECONDS` - Delay between each metrics job to prevent API flooding (default: `0.2`)

**Background Job Configuration:**
- `SOLID_QUEUE_CONCURRENCY` - Number of concurrent background job workers (default: `5` for production, `1` for development)
- `RAILS_MAX_THREADS` - Puma thread count (default: `5`)

**Database & Security:**
- `DATABASE_URL` - PostgreSQL connection string
- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` - Encryption key for API tokens (64-character hex string)
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` - Deterministic encryption key (64-character hex string)
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` - Key derivation salt (64-character hex string)
- `SECRET_KEY_BASE` - Rails secret key base

### Rate Limiting Behavior

The application implements comprehensive rate limit handling:

1. **Pre-request Waiting**: Before making API calls, checks if desk has a `wait_till` timestamp and sleeps if needed
2. **Header-based Throttling**: Monitors `X-Rate-Limit` headers and backs off when remaining calls drop below the configured headroom percentage
3. **429 Error Handling**: Detects 429 (Too Many Requests) responses, extracts `Retry-After` header, and updates desk's `wait_till` timestamp
4. **Retry Logic**: Automatically retries requests up to 3 times with progressive backoff
5. **Persistent State**: Rate limit wait states are stored in the database and survive job failures or restarts

## Deployment

This application is deployed using Docker and Docker Compose. See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed deployment instructions covering:
- Coolify deployment options (with external or internal PostgreSQL)
- Environment configuration and magic variables
- Admin user setup with automatic seeding

Available Docker Compose configurations:
- `docker-compose.yml` - Standard deployment with internal PostgreSQL (includes postgres, web, worker, migrate, seed services)
- `docker-compose-coolify.yml` - Coolify-optimized deployment with internal PostgreSQL and Coolify magic variables (includes postgres, web, worker, migrate, seed services)

**Note**: The DEPLOYMENT.md file is outdated and references MongoDB configurations and additional docker-compose files that do not exist. The application **only uses PostgreSQL** (no MongoDB), and only the two compose files listed above exist in the repository.

## Reporting & Analytics

Once deployed and syncing data, you can connect your reporting tool of choice directly to the PostgreSQL database:

- Connection details are available in your deployment environment variables (`DATABASE_URL`)
- Query the `zendesk_tickets` table for ticket data
- Use indexed columns for fast queries on common fields
- Use JSONB operators to query custom fields in the `raw_data` column

Examples:
```sql
-- Query tickets by status
SELECT * FROM zendesk_tickets 
WHERE status = 'open' AND domain = 'yourcompany.zendesk.com';

-- Query custom fields from JSONB
SELECT zendesk_id, raw_data->>'custom_field_12345' as custom_value 
FROM zendesk_tickets 
WHERE domain = 'yourcompany.zendesk.com';

-- Aggregate ticket metrics with indexed columns
SELECT 
  status, 
  COUNT(*) as ticket_count,
  AVG(full_resolution_time_in_minutes) as avg_resolution_minutes,
  AVG(first_reply_time_in_minutes) as avg_first_reply_minutes,
  AVG(agent_wait_time_in_minutes) as avg_agent_wait_minutes
FROM zendesk_tickets 
WHERE domain = 'yourcompany.zendesk.com' 
GROUP BY status;

-- Query tickets with comments from JSONB
SELECT 
  zendesk_id, 
  subject,
  jsonb_array_length(raw_data->'comments') as comment_count
FROM zendesk_tickets 
WHERE domain = 'yourcompany.zendesk.com'
  AND raw_data->'comments' IS NOT NULL;

-- Get tickets with high resolution times
SELECT zendesk_id, subject, status, full_resolution_time_in_minutes
FROM zendesk_tickets
WHERE domain = 'yourcompany.zendesk.com'
  AND full_resolution_time_in_minutes > 1440  -- More than 24 hours
ORDER BY full_resolution_time_in_minutes DESC;
```

## Development

### Local Setup

The repository includes two Docker Compose configurations:
- `docker-compose.yml` - Standard deployment with internal PostgreSQL
- `docker-compose-coolify.yml` - Coolify-optimized deployment with internal PostgreSQL and Coolify magic variables

For local development, use `docker-compose.yml`:

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
```

**Environment Variables for Local Development:**

Create a `.env` file in the project root with:
```
RAILS_ENV=development
SECRET_KEY_BASE=development_secret_key_base_change_this_in_production
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=00000000000000000000000000000000
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=00000000000000000000000000000000
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=00000000000000000000000000000000
DEFAULT_ADMIN_USER=admin@example.com
DEFAULT_ADMIN_PW=password
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=zd_desk_data_collector_development
```

**Note**: The `docker-compose.yml` file is configured to automatically construct the `DATABASE_URL` from these PostgreSQL environment variables, so you don't need to set `DATABASE_URL` explicitly for local development.

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
