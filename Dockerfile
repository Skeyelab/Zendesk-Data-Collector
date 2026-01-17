# Base stage for shared dependencies
FROM ruby:3.2.4-slim AS base

# Install system dependencies
RUN apt-get update -qq && \
    apt-get install -y \
    build-essential \
    libpq-dev \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Development stage
FROM base AS development

# Install development dependencies (needed for gem compilation)
RUN apt-get update -qq && \
    apt-get install -y \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install gems (including development and test groups for local development)
RUN bundle install

# Copy application code
COPY . .

# Create necessary directories for Rails (log, tmp, storage) before switching user
RUN mkdir -p log tmp/pids tmp/cache tmp/sockets tmp/storage storage && \
    chmod -R 755 log tmp storage

# Create a non-root user
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app
USER appuser

# Production stage
FROM base AS production

# Install minimal production dependencies
RUN apt-get update -qq && \
    apt-get install -y \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install gems without development and test groups
RUN bundle install --without development test && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy application code
COPY . .

# Create necessary directories for Rails (log, tmp, storage) before switching user
RUN mkdir -p log tmp/pids tmp/cache tmp/sockets tmp/storage storage && \
    mkdir -p public/assets && \
    chmod -R 755 public log tmp storage

# Create a non-root user
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 3000

# Default command (can be overridden in docker-compose)
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
