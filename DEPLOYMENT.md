# Deployment Guide

This guide covers deploying the Zendesk Data Collector application using Docker Compose on Coolify and locally for development.

## Overview

This project uses two Docker Compose configurations:

- **`docker-compose.yml`** - Standard deployment with internal PostgreSQL
- **`docker-compose-coolify.yml`** - Coolify-optimized deployment with internal PostgreSQL and Coolify magic variables

Both configurations use PostgreSQL exclusively for all data storage (tickets, admin users, desk configurations, and job queue).

## Coolify Deployment

### Standard Deployment (docker-compose.yml)

Use `docker-compose.yml` for a standard deployment with internal PostgreSQL.

#### Setup Steps

1. **Create Service Stack in Coolify**
   - Go to your Coolify project
   - Create a new **Service Stack** resource
   - Select **Docker Compose** as the build method
   - Point to your Git repository
   - Specify `docker-compose.yml` as the compose file (or set it as default)

2. **Set Environment Variables**

   In Coolify's Environment Variables section, set:

   **Required:**
   - `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` - 64-character hex string (32 bytes) for encryption (generate with `SecureRandom.hex(32)`)
   - `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` - 64-character hex string (32 bytes) for deterministic encryption (generate with `SecureRandom.hex(32)`)
   - `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` - 64-character hex string (32 bytes) for key derivation (generate with `SecureRandom.hex(32)`)
   - Optionally: `SECRET_KEY_BASE` - If not using the magic variable (see below)

   **Recommended for Initial Setup:**
   - `DEFAULT_ADMIN_USER` - Email address for the initial admin user (e.g., `admin@example.com`)
   - `DEFAULT_ADMIN_PW` - Password for the initial admin user (optional - can use `SERVICE_PASSWORD_ADMIN` magic variable instead)

   **Webhook Security (Required for n8n integration):**
   - `WEBHOOKS_TICKETS_SECRET` - Secure random string for webhook authentication (generate with `openssl rand -hex 32`)

   **Optional PostgreSQL Configuration:**
   - `POSTGRES_USER` - PostgreSQL username (default: `postgres`)
   - `POSTGRES_PASSWORD` - PostgreSQL password (default: uses `SERVICE_PASSWORD_POSTGRES` magic variable, or `postgres`)
   - `POSTGRES_DB` - Database name (default: `zd_desk_data_collector_production`)

   **Optional:**
   - `RAILS_MAX_THREADS=5` - Puma thread count
   - `RAILS_SERVE_STATIC_FILES=true` - Serve precompiled assets from Rails
   - `SOLID_QUEUE_CONCURRENCY=5` - Background job concurrency

3. **Magic Environment Variables**

   Coolify automatically generates magic variables when referenced in `docker-compose.yml`:

   - `SERVICE_PASSWORD_WEB` - Auto-generated 32-character password (used for `SECRET_KEY_BASE`)
   - `SERVICE_PASSWORD_POSTGRES` - Auto-generated password for PostgreSQL (if not set, uses `POSTGRES_PASSWORD` or defaults to `postgres`)
   - `SERVICE_PASSWORD_ADMIN` - Auto-generated password (used for `DEFAULT_ADMIN_PW` if referenced)
   - `SERVICE_URL_WEB` - Auto-populated web service URL
   - `SERVICE_FQDN_WEB` - Auto-populated fully qualified domain name

   These are automatically available to all services in the compose file.

4. **Assign Domain**

   - Assign a domain to the `web` service: `http://your-app.com:3000`
   - The `:3000` tells Coolify the container port
   - Coolify's proxy will route external traffic (port 80/443) to container port 3000

5. **Deploy**

   - Click Deploy in Coolify
   - Coolify will build the Docker image and start services
   - The `migrate` service will run once to execute database migrations
   - The `seed` service will run once after migrations to create the default admin user (if `DEFAULT_ADMIN_USER` and `DEFAULT_ADMIN_PW` are set)

### Coolify-Optimized Deployment (docker-compose-coolify.yml)

Use `docker-compose-coolify.yml` for a Coolify-optimized deployment with enhanced magic variable support.

#### Setup Steps

1. **Create Service Stack in Coolify**
   - Go to your Coolify project
   - Create a new **Service Stack** resource
   - Select **Docker Compose** as the build method
   - Point to your Git repository
   - **Important**: Specify `docker-compose-coolify.yml` as the compose file

2. **Set Environment Variables**

   Same as standard deployment above. The Coolify-optimized file includes additional Coolify-specific optimizations.

3. **Deploy**

   Follow the same deployment steps as the standard deployment.

### Services in Coolify Deployment

Both compose files include:
- **postgres** - PostgreSQL 16 database with persistent storage
- **web** - Rails application (Puma server) on port 3000
- **worker** - Solid Queue background job processor (excluded from health checks)
- **migrate** - Database migrations (runs once, then stops)
- **seed** - Database seeding (runs once after migrate, creates admin user if configured)

### Setting Up Default Admin User

To create an initial admin user for login, you have two options:

**Option 1: Use Magic Variables (Recommended)**
- Set **`DEFAULT_ADMIN_USER`** - The email address for the admin user (e.g., `admin@example.com`)
- Coolify will automatically generate **`SERVICE_PASSWORD_ADMIN`** - A secure auto-generated password

The compose files are configured to use `SERVICE_PASSWORD_ADMIN` automatically if available, falling back to a manually set `DEFAULT_ADMIN_PW` if needed.

**Option 2: Manual Password**
- Set **`DEFAULT_ADMIN_USER`** - The email address for the admin user
- Set **`DEFAULT_ADMIN_PW`** - Your chosen password

**How It Works:**
- These variables are used by the `seed` service which runs automatically after migrations on first deployment
- The password uses the pattern: `${SERVICE_PASSWORD_ADMIN:-${DEFAULT_ADMIN_PW}}` - meaning it will use the magic variable if available, otherwise your manual password
- If `DEFAULT_ADMIN_USER` is not set, the seed step will skip creating an admin user (you'll see a message in the logs)
- The generated password will appear in Coolify's Environment Variables UI for your reference

**Important**: After the first deployment, if you need to create additional admin users or change passwords, you can do so through the Avo admin interface or by running `rails console` in the web service container.

### Troubleshooting

- **Magic Variables Not Working**: Requires Coolify v4.0.0-beta.411+ for Git-based deployments
- **Migrations Not Running**: Check the `migrate` service logs in Coolify
- **PostgreSQL Connection Issues**: Verify that services wait for PostgreSQL health check before starting

## Local Development

### Prerequisites

- Docker and Docker Compose installed
- Optional: `.env` file for custom environment variables

### Setup Steps

1. **Create Environment File**

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

2. **Start Services**

   ```bash
   docker-compose up
   ```

   This will start:
   - PostgreSQL (port 5432)
   - Rails web server (port 3000)
   - Solid Queue worker

3. **Run Database Migrations**

   ```bash
   docker-compose run web rails db:migrate
   ```

4. **Seed Database (Optional)**

   ```bash
   docker-compose run web rails db:seed
   ```

5. **Access Application**

   - Web interface: http://localhost:3000
   - Admin interface: http://localhost:3000/avo
   - PostgreSQL: localhost:5432

### Local Development Services

- **postgres** - PostgreSQL 16 database
- **web** - Rails application
- **worker** - Solid Queue worker

### Useful Commands

**View Logs:**
```bash
docker-compose logs -f web
docker-compose logs -f worker
```

**Run Rails Console:**
```bash
docker-compose run web rails console
```

**Run Tests:**
```bash
docker-compose run web rails test
```

**Run Rails Generator:**
```bash
docker-compose run web rails generate model User
```

**Stop Services:**
```bash
docker-compose down
```

**Remove Volumes (fresh start):**
```bash
docker-compose down -v
```

**Rebuild Containers:**
```bash
docker-compose build --no-cache
```

## Key Differences

| Feature | docker-compose.yml | docker-compose-coolify.yml | Local Development |
|---------|-------------------|---------------------------|-------------------|
| PostgreSQL | Included in stack | Included in stack | Included |
| Environment | production | production | development |
| Code Volumes | None (code in image) | None (code in image) | Mounted for hot-reload |
| Secrets | Magic variables (`SERVICE_PASSWORD_WEB`, `SERVICE_PASSWORD_POSTGRES`) | Magic variables (enhanced support) | `.env` file or defaults |
| Asset Precompilation | Handled in Dockerfile | Handled in Dockerfile | Not needed (development) |
| Health Checks | Worker/migrate/postgres excluded | Worker/migrate/postgres excluded | All enabled |
| Build Target | production | production | development |

## Environment Variables Reference

### Production (Coolify)

- `RAILS_ENV=production`
- `SECRET_KEY_BASE` - Auto-generated via `SERVICE_PASSWORD_WEB` or manually set
- `DATABASE_URL` - Auto-constructed from PostgreSQL environment variables
- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` - 64-character hex string for Active Record encryption (required)
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` - 64-character hex string for deterministic encryption (required)
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` - 64-character hex string for key derivation (required)
- `DEFAULT_ADMIN_USER` - Email for initial admin user (recommended for first deployment)
- `DEFAULT_ADMIN_PW` - Password for initial admin user (recommended for first deployment)
- `WEBHOOKS_TICKETS_SECRET` - Secure random string for webhook authentication (required for n8n integration)
- `RAILS_LOG_TO_STDOUT=true` - For log aggregation
- `RAILS_SERVE_STATIC_FILES=true` - Serve assets from Rails
- `RAILS_MAX_THREADS=5` - Puma thread count
- `PORT=3000` - Server port
- `SOLID_QUEUE_CONCURRENCY=5` - Background job concurrency
- `POSTGRES_USER` - PostgreSQL username (default: `postgres`)
- `POSTGRES_PASSWORD` - PostgreSQL password (default: uses `SERVICE_PASSWORD_POSTGRES` or `postgres`)
- `POSTGRES_DB` - Database name (default: `zd_desk_data_collector_production`)

### Development (Local)

- `RAILS_ENV=development`
- `SECRET_KEY_BASE` - Default development key (can override in `.env`)
- `DATABASE_URL` - Set automatically to local postgres service
- `SOLID_QUEUE_CONCURRENCY=1` - Lower concurrency for development
- `POSTGRES_USER` - PostgreSQL username (default: `postgres`)
- `POSTGRES_PASSWORD` - PostgreSQL password (default: `postgres`)
- `POSTGRES_DB` - Database name (default: `zd_desk_data_collector_development`)

## Additional Resources

- [Coolify Docker Compose Documentation](https://coolify.io/docs/knowledge-base/docker/compose)
- [Coolify Magic Environment Variables](https://coolify.io/docs/knowledge-base/docker/compose#coolify-s-magic-environment-variables)
- [Coolify Environment Variables Guide](https://coolify.io/docs/knowledge-base/environment-variables)
