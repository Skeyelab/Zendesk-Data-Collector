# Zendesk-Data-Collector

This Rails application extracts all ticket data from Zendesk in real time to a PostgreSQL database. It automatically handles all fields, including dynamically created custom fields, using JSONB for flexible schema support.

## Deployment

This application is deployed using Docker and Docker Compose. See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed deployment instructions covering:
- Coolify deployment options (with external or internal databases)
- Local development setup
- Environment configuration

The point of this app is to then attach a reporting package to the database to create fully customized, real time reports.

During deployment, you will configure an admin user account. This is used to login to the system at your deployed URL at `/admin/login`. Once logged in, you will add your Zendesk accounts with a username and API token.

If your desk is "active" in the admin panel, the system will collect data from the API and populate the PostgreSQL database with ticket data.

## Data Storage Architecture

The application uses PostgreSQL for all data storage:

- **PostgreSQL** - Stores all Zendesk ticket data (with JSONB for dynamic fields), admin user accounts, desk configuration records, and background job queue

Common ticket fields are stored as indexed columns for fast queries, while the complete API response (including custom fields) is stored in a JSONB column. This provides both performance and flexibility.

At this point you can use your reporting tool of choice with PostgreSQL. You can find the connection info in your deployment environment variables.
