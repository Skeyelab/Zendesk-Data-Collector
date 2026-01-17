# Zendesk-Data-Collector

This Rails application extracts all ticket data from Zendesk in real time to a PostgreSQL database. It automatically creates all columns needed, even when a new custom field is created.

## Deployment

This application is deployed using Docker and Docker Compose. See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed deployment instructions covering:
- Coolify deployment options (with external or internal databases)
- Local development setup
- Environment configuration

The point of this app is to then attach a reporting package to the database to create fully customized, real time reports.

During deployment, you will configure an admin user account. This is used to login to the system at your deployed URL at `/admin/login`. Once logged in, you will add your Zendesk accounts with a username and API token.

If your desk is "active" in the admin panel, the system will collect data from the API and populate a table in the postgres database.

At this point you can use your reporting tool of choice with the DB. You can find the connection info in your deployment environment variables.
