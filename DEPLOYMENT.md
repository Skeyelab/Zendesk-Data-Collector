# Deployment Guide

This guide covers deploying the Zendesk Data Collector application using Docker Compose on Coolify and locally for development.

## Overview

This project uses four Docker Compose configurations:

- **`docker-compose.yml`** - For Coolify deployment with external PostgreSQL and MongoDB
- **`docker-compose.coolify-pg.yml`** - For Coolify deployment with internal PostgreSQL and external MongoDB
- **`docker-compose.coolify-full.yml`** - For Coolify deployment with both internal PostgreSQL and MongoDB
- **`docker-compose.local.yml`** - For local development

### Which Compose File Should I Use?

- **`docker-compose.yml`**: Use when you already have both PostgreSQL and MongoDB running in Coolify and want to connect to them
- **`docker-compose.coolify-pg.yml`**: Use when you want PostgreSQL managed within the same stack but MongoDB is external
- **`docker-compose.coolify-full.yml`**: Use when you want both databases managed within the same stack (fully self-contained)
- **`docker-compose.local.yml`**: Use for local development with all services included

## Coolify Deployment

### Option 1: External PostgreSQL and MongoDB

Use `docker-compose.yml` when both databases are already running in Coolify.

#### Prerequisites

- PostgreSQL and MongoDB services already running in your Coolify project
- Access to database connection strings from those services

#### Setup Steps

1. **Create Service Stack in Coolify**
   - Go to your Coolify project
   - Create a new **Service Stack** resource
   - Select **Docker Compose** as the build method
   - Point to your Git repository
   - Specify `docker-compose.yml` as the compose file (or set it as default)

2. **Configure Database Connections**
   - Enable **"Connect to Predefined Network"** option on the Service Stack page
   - This allows your Rails app to connect to existing PostgreSQL and MongoDB services

3. **Set Environment Variables**

   In Coolify's Environment Variables section, set:

   **Required:**
   - `DATABASE_URL` - PostgreSQL connection string from your existing PostgreSQL service (use internal URL)
   - `MONGODB_URI` - MongoDB connection string from your existing MongoDB service (use internal URL)
   - `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` - 64-character hex string (32 bytes) for encryption (generate with `SecureRandom.hex(32)`)
   - `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` - 64-character hex string (32 bytes) for deterministic encryption (generate with `SecureRandom.hex(32)`)
   - `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` - 64-character hex string (32 bytes) for key derivation (generate with `SecureRandom.hex(32)`)
   - Optionally: `SECRET_KEY_BASE` - If not using the magic variable (see below)

   **Recommended for Initial Setup:**
   - `DEFAULT_ADMIN_USER` - Email address for the initial admin user (e.g., `admin@example.com`)
   - `DEFAULT_ADMIN_PW` - Password for the initial admin user (must be at least 12 characters - optional, can use `SERVICE_PASSWORD_ADMIN` magic variable instead)

   **Optional:**
   - `RAILS_MAX_THREADS=5` - Puma thread count
   - `RAILS_SERVE_STATIC_FILES=true` - Serve precompiled assets from Rails
   - `SOLID_QUEUE_CONCURRENCY=5` - Background job concurrency

   **Using Shared Variables:**
   You can reference shared variables (Team/Project/Environment level) using:
   ```
   DATABASE_URL={{environment.DATABASE_URL}}
   MONGODB_URI={{environment.MONGODB_URI}}
   ```

4. **Magic Environment Variables**

   Coolify automatically generates magic variables when referenced in `docker-compose.yml`:

   - `SERVICE_PASSWORD_WEB` - Auto-generated 32-character password (used for `SECRET_KEY_BASE`)
   - `SERVICE_PASSWORD_ADMIN` - Auto-generated password (used for `DEFAULT_ADMIN_PW` if referenced)
   - `SERVICE_URL_WEB` - Auto-populated web service URL
   - `SERVICE_FQDN_WEB` - Auto-populated fully qualified domain name

   These are automatically available to all services in the compose file. Both `SECRET_KEY_BASE` and `DEFAULT_ADMIN_PW` will use their respective magic variables if available, otherwise falling back to manually set values.

5. **Assign Domain**

   - Assign a domain to the `web` service: `http://your-app.com:3000`
   - The `:3000` tells Coolify the container port
   - Coolify's proxy will route external traffic (port 80/443) to container port 3000

6. **Deploy**

   - Click Deploy in Coolify
   - Coolify will build the Docker image and start services
   - The `migrate` service will run once to execute database migrations
   - The `seed` service will run once after migrations to create the default admin user (if `DEFAULT_ADMIN_USER` and `DEFAULT_ADMIN_PW` are set)

### Option 2: Internal PostgreSQL and External MongoDB

Use `docker-compose.coolify-pg.yml` when you want PostgreSQL managed within the stack but MongoDB is external.

#### Prerequisites

- MongoDB service already running in your Coolify project
- Access to MongoDB connection string

#### Setup Steps

1. **Create Service Stack in Coolify**
   - Go to your Coolify project
   - Create a new **Service Stack** resource
   - Select **Docker Compose** as the build method
   - Point to your Git repository
   - **Important**: Specify `docker-compose.coolify-pg.yml` as the compose file

2. **Configure MongoDB Connection**
   - Enable **"Connect to Predefined Network"** option on the Service Stack page
   - This allows your Rails app to connect to existing MongoDB service

3. **Set Environment Variables**

   **Required:**
   - `MONGODB_URI` - MongoDB connection string from your existing MongoDB service (use internal URL)
   - `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` - 64-character hex string (32 bytes) for encryption (generate with `SecureRandom.hex(32)`)
   - `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` - 64-character hex string (32 bytes) for deterministic encryption (generate with `SecureRandom.hex(32)`)
   - `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` - 64-character hex string (32 bytes) for key derivation (generate with `SecureRandom.hex(32)`)
   - Optionally: `SECRET_KEY_BASE` - If not using the magic variable

   **Recommended for Initial Setup:**
   - `DEFAULT_ADMIN_USER` - Email address for the initial admin user (e.g., `admin@example.com`)
   - `DEFAULT_ADMIN_PW` - Password for the initial admin user (must be at least 12 characters - optional, can use `SERVICE_PASSWORD_ADMIN` magic variable instead)

   **Optional PostgreSQL Configuration:**
   - `POSTGRES_USER` - PostgreSQL username (default: `postgres`)
   - `POSTGRES_PASSWORD` - PostgreSQL password (default: uses `SERVICE_PASSWORD_POSTGRES` magic variable, or `postgres`)
   - `POSTGRES_DB` - Database name (default: `zd_desk_data_collector_production`)

   **Optional:**
   - `RAILS_MAX_THREADS=5` - Puma thread count
   - `RAILS_SERVE_STATIC_FILES=true` - Serve precompiled assets from Rails
   - `SOLID_QUEUE_CONCURRENCY=5` - Background job concurrency

4. **Magic Environment Variables**

   Additional magic variables available:
   - `SERVICE_PASSWORD_POSTGRES` - Auto-generated password for PostgreSQL (if not set, uses `POSTGRES_PASSWORD` or defaults to `postgres`)
   - All other magic variables from Option 1 also apply

5. **Assign Domain**

   - Assign a domain to the `web` service: `http://your-app.com:3000`

6. **Deploy**

   - Click Deploy in Coolify
   - PostgreSQL will be created automatically with persistent storage
   - The `migrate` service will run once to execute database migrations
   - The `seed` service will run once after migrations to create the default admin user (if `DEFAULT_ADMIN_USER` and `DEFAULT_ADMIN_PW` are set)

### Option 3: Internal PostgreSQL and MongoDB (Fully Self-Contained)

Use `docker-compose.coolify-full.yml` when you want both databases managed within the same stack. This is the most self-contained option.

#### Prerequisites

- No external database services needed

#### Setup Steps

1. **Create Service Stack in Coolify**
   - Go to your Coolify project
   - Create a new **Service Stack** resource
   - Select **Docker Compose** as the build method
   - Point to your Git repository
   - **Important**: Specify `docker-compose.coolify-full.yml` as the compose file

2. **Set Environment Variables**

   **Optional PostgreSQL Configuration:**
   - `POSTGRES_USER` - PostgreSQL username (default: `postgres`)
   - `POSTGRES_PASSWORD` - PostgreSQL password (default: uses `SERVICE_PASSWORD_POSTGRES` magic variable, or `postgres`)
   - `POSTGRES_DB` - Database name (default: `zd_desk_data_collector_production`)

   **Optional MongoDB Configuration:**
   - `MONGO_ROOT_USERNAME` - MongoDB root username (default: `admin`)
   - `MONGO_ROOT_PASSWORD` - MongoDB root password (default: uses `SERVICE_PASSWORD_MONGODB` magic variable, or `admin`)

   **Recommended for Initial Setup:**
   - `DEFAULT_ADMIN_USER` - Email address for the initial admin user (e.g., `admin@example.com`)
   - `DEFAULT_ADMIN_PW` - Password for the initial admin user (must be at least 12 characters - optional, can use `SERVICE_PASSWORD_ADMIN` magic variable instead)

   **Required for Active Record Encryption:**
   - `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` - 64-character hex string (32 bytes) for encryption (generate with `SecureRandom.hex(32)`)
   - `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` - 64-character hex string (32 bytes) for deterministic encryption (generate with `SecureRandom.hex(32)`)
   - `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` - 64-character hex string (32 bytes) for key derivation (generate with `SecureRandom.hex(32)`)

   **Optional:**
   - Optionally: `SECRET_KEY_BASE` - If not using the magic variable
   - `RAILS_MAX_THREADS=5` - Puma thread count
   - `RAILS_SERVE_STATIC_FILES=true` - Serve precompiled assets from Rails
   - `SOLID_QUEUE_CONCURRENCY=5` - Background job concurrency

3. **Magic Environment Variables**

   Magic variables available:
   - `SERVICE_PASSWORD_WEB` - Auto-generated password for Rails `SECRET_KEY_BASE`
   - `SERVICE_PASSWORD_POSTGRES` - Auto-generated password for PostgreSQL (if not set, uses `POSTGRES_PASSWORD` or defaults to `postgres`)
   - `SERVICE_PASSWORD_MONGODB` - Auto-generated password for MongoDB (if not set, uses `MONGO_ROOT_PASSWORD` or defaults to `admin`)
   - `SERVICE_URL_WEB` - Auto-populated web service URL
   - `SERVICE_FQDN_WEB` - Auto-populated fully qualified domain name

4. **Assign Domain**

   - Assign a domain to the `web` service: `http://your-app.com:3000`

5. **Deploy**

   - Click Deploy in Coolify
   - Both PostgreSQL and MongoDB will be created automatically with persistent storage
   - The `migrate` service will run once to execute database migrations
   - The `seed` service will run once after migrations to create the default admin user (if `DEFAULT_ADMIN_USER` and `DEFAULT_ADMIN_PW` are set)

6. **No Network Configuration Needed**

   - No need to enable "Connect to Predefined Network" since all services are in the same stack

### Services in Coolify Deployment

**Option 1 (docker-compose.yml):**
- **web** - Rails application (Puma server) on port 3000
- **worker** - Solid Queue background job processor (excluded from health checks)
- **migrate** - Database migrations (runs once, then stops)
- **seed** - Database seeding (runs once after migrate, creates admin user if configured)

**Option 2 (docker-compose.coolify-pg.yml):**
- **postgres** - PostgreSQL 16 database with persistent storage
- **web** - Rails application (Puma server) on port 3000
- **worker** - Solid Queue background job processor (excluded from health checks)
- **migrate** - Database migrations (runs once, then stops)
- **seed** - Database seeding (runs once after migrate, creates admin user if configured)

**Option 3 (docker-compose.coolify-full.yml):**
- **postgres** - PostgreSQL 16 database with persistent storage
- **mongodb** - MongoDB 7 database with persistent storage
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
- Set **`DEFAULT_ADMIN_PW`** - Your chosen password (must be at least 12 characters)

**How It Works:**
- These variables are used by the `seed` service which runs automatically after migrations on first deployment
- The password uses the pattern: `${SERVICE_PASSWORD_ADMIN:-${DEFAULT_ADMIN_PW}}` - meaning it will use the magic variable if available, otherwise your manual password
- Passwords must be at least 12 characters long
- If `DEFAULT_ADMIN_USER` is not set, the seed step will skip creating an admin user (you'll see a message in the logs)
- The generated password will appear in Coolify's Environment Variables UI for your reference

**Important**: After the first deployment, if you need to create additional admin users or change passwords, you can do so through the Avo admin interface or by running `rails console` in the web service container.

### Troubleshooting

- **Database Connection Issues**:
  - Option 1: Ensure "Connect to Predefined Network" is enabled and you're using internal connection strings
  - Option 2: Ensure "Connect to Predefined Network" is enabled for MongoDB connection
- **Magic Variables Not Working**: Requires Coolify v4.0.0-beta.411+ for Git-based deployments
- **Migrations Not Running**: Check the `migrate` service logs in Coolify
- **PostgreSQL Connection Issues (Option 2)**: Verify that services wait for PostgreSQL health check before starting

## Local Development

### Prerequisites

- Docker and Docker Compose installed
- Optional: `.env` file for custom environment variables (copy from `.env.example`)

### Setup Steps

1. **Start Services**

   ```bash
   docker-compose -f docker-compose.local.yml up
   ```

   This will start:
   - PostgreSQL (port 5432)
   - MongoDB (port 27017)
   - Rails web server (port 3000)
   - Solid Queue worker

2. **Run Database Migrations**

   ```bash
   docker-compose -f docker-compose.local.yml run web rails db:migrate
   ```

3. **Seed Database (Optional)**

   ```bash
   docker-compose -f docker-compose.local.yml run web rails db:seed
   ```

4. **Access Application**

   - Web interface: http://localhost:3000
   - PostgreSQL: localhost:5432
   - MongoDB: localhost:27017

### Local Development Services

- **postgres** - PostgreSQL 16 database
- **mongodb** - MongoDB 7 database
- **web** - Rails application with code mounted for hot-reload
- **worker** - Solid Queue worker with code mounted

### Useful Commands

**View Logs:**
```bash
docker-compose -f docker-compose.local.yml logs -f web
docker-compose -f docker-compose.local.yml logs -f worker
```

**Run Rails Console:**
```bash
docker-compose -f docker-compose.local.yml run web rails console
```

**Run Rails Generator:**
```bash
docker-compose -f docker-compose.local.yml run web rails generate model User
```

**Stop Services:**
```bash
docker-compose -f docker-compose.local.yml down
```

**Remove Volumes (fresh start):**
```bash
docker-compose -f docker-compose.local.yml down -v
```

**Rebuild Containers:**
```bash
docker-compose -f docker-compose.local.yml build --no-cache
```

## Key Differences

| Feature | docker-compose.yml (Coolify - External DBs) | docker-compose.coolify-pg.yml (Coolify - Internal PG) | docker-compose.coolify-full.yml (Coolify - Internal DBs) | docker-compose.local.yml (Local) |
|---------|---------------------------------------------|-------------------------------------------------------|----------------------------------------------------------|----------------------------------|
| PostgreSQL | External (existing service) | Included in stack | Included in stack | Included |
| MongoDB | External (existing service) | External (existing service) | Included in stack | Included |
| Environment | production | production | production | development |
| Code Volumes | None (code in image) | None (code in image) | None (code in image) | Mounted for hot-reload |
| Secrets | Magic variables (`SERVICE_PASSWORD_WEB`) | Magic variables (`SERVICE_PASSWORD_WEB`, `SERVICE_PASSWORD_POSTGRES`) | Magic variables (`SERVICE_PASSWORD_WEB`, `SERVICE_PASSWORD_POSTGRES`, `SERVICE_PASSWORD_MONGODB`) | `.env` file or defaults |
| Asset Precompilation | Handled in Dockerfile | Handled in Dockerfile | Handled in Dockerfile | Not needed (development) |
| Health Checks | Worker/migrate excluded | Worker/migrate/postgres excluded | Worker/migrate/postgres/mongodb excluded | All enabled |
| Build Target | production | production | production | development |
| Network Configuration | Connect to Predefined Network | Connect to Predefined Network (for MongoDB) | No special network config needed | Internal Docker network |

## Environment Variables Reference

### Production (Coolify)

- `RAILS_ENV=production`
- `SECRET_KEY_BASE` - Auto-generated via `SERVICE_PASSWORD_WEB` or manually set
- `DATABASE_URL` - PostgreSQL connection string
- `MONGODB_URI` - MongoDB connection string
- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` - 64-character hex string for Active Record encryption (required)
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` - 64-character hex string for deterministic encryption (required)
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` - 64-character hex string for key derivation (required)
- `DEFAULT_ADMIN_USER` - Email for initial admin user (recommended for first deployment)
- `DEFAULT_ADMIN_PW` - Password for initial admin user, minimum 12 characters (recommended for first deployment)
- `RAILS_LOG_TO_STDOUT=true` - For log aggregation
- `RAILS_SERVE_STATIC_FILES=true` - Serve assets from Rails
- `RAILS_MAX_THREADS=5` - Puma thread count
- `PORT=3000` - Server port
- `SOLID_QUEUE_CONCURRENCY=5` - Background job concurrency

### Development (Local)

- `RAILS_ENV=development`
- `SECRET_KEY_BASE` - Default development key (can override in `.env`)
- `DATABASE_URL` - Set automatically to local postgres service
- `MONGODB_URI` - Set automatically to local mongodb service
- `SOLID_QUEUE_CONCURRENCY=1` - Lower concurrency for development

## Additional Resources

- [Coolify Docker Compose Documentation](https://coolify.io/docs/knowledge-base/docker/compose)
- [Coolify Magic Environment Variables](https://coolify.io/docs/knowledge-base/docker/compose#coolify-s-magic-environment-variables)
- [Coolify Environment Variables Guide](https://coolify.io/docs/knowledge-base/environment-variables)
