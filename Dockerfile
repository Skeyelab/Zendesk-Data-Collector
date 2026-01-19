# syntax=docker/dockerfile:1.4

# Base stage for shared dependencies
FROM ruby:3.2.4-slim AS base

# Install system dependencies in a single layer with cache cleanup
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Development stage
FROM base AS development

# Install development dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

# Copy Gemfile and Gemfile.lock first (for better caching)
COPY Gemfile Gemfile.lock ./

# Install gems with cache mount for faster rebuilds
RUN --mount=type=cache,target=/usr/local/bundle/cache \
    bundle install

# Create non-root user before copying code (allows COPY --chown)
RUN useradd -m -u 1000 appuser && \
    mkdir -p log tmp/pids tmp/cache tmp/sockets tmp/storage storage && \
    chmod -R 755 log tmp storage

# Copy application code with correct ownership
COPY --chown=appuser:appuser . .

USER appuser

# Production stage
FROM base AS production

# Copy Gemfile and Gemfile.lock first (for better caching)
COPY Gemfile Gemfile.lock ./

# Install gems with cache mount and cleanup in same layer
RUN --mount=type=cache,target=/usr/local/bundle/cache \
    bundle install --without development test --jobs=4 --retry=3 && \
    rm -rf ~/.bundle/ /usr/local/bundle/cache && \
    find /usr/local/bundle/gems -name "*.git" -type d -exec rm -rf {} + 2>/dev/null || true

# Create non-root user and directories before copying code
RUN useradd -m -u 1000 appuser && \
    mkdir -p log tmp/pids tmp/cache tmp/sockets tmp/storage storage public && \
    chmod -R 755 public log tmp storage

# Copy application code with correct ownership
COPY --chown=appuser:appuser . .

USER appuser

# Expose port
EXPOSE 3000

# Default command (can be overridden in docker-compose)
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
