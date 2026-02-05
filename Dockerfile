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

# Ensure gem executables are on PATH for all users (fixes "command not found: puma" in some runtimes)
ENV GEM_HOME=/usr/local/bundle
ENV PATH=/usr/local/bundle/bin:$PATH

# Match Gemfile.lock "BUNDLED WITH" so bundle install works (ruby image ships with Bundler 2.x)
RUN gem install bundler -v 4.0.6

# Development stage
FROM base AS development

# Install development dependencies
RUN apt-get update -qq && \
    apt-get install -y \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

# Copy Gemfile and Gemfile.lock first (for better caching)
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle install

# Create non-root user and set ownership
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

# Copy application code with correct ownership
COPY --chown=appuser:appuser . .

# Ensure directories exist with correct permissions (as root, before switching)
RUN mkdir -p log tmp/pids tmp/cache tmp/sockets tmp/storage storage && \
    chown -R appuser:appuser log tmp storage

# Switch to appuser
USER appuser

# Production stage
FROM base AS production

# Copy Gemfile and Gemfile.lock first (for better caching)
COPY Gemfile Gemfile.lock ./

# Install gems without development and test groups (BUNDLE_PATH so install location is explicit)
ENV BUNDLE_PATH=/usr/local/bundle
RUN bundle install --without development test && \
    rm -rf ~/.bundle && \
    find /usr/local/bundle/gems -name "*.git" -type d -exec rm -rf {} + 2>/dev/null || true

# Create non-root user and set /app ownership
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

# Copy application code with correct ownership
COPY --chown=appuser:appuser . .

# Precompile assets for production (Propshaft creates manifest and fingerprinted assets)
# This ensures Mission Control Jobs and other engine assets are available
ENV RAILS_ENV=production
ENV SECRET_KEY_BASE=dummy_for_precompile
RUN bundle exec rails assets:precompile || true

# Ensure directories exist with correct permissions (as root, before switching)
RUN mkdir -p log tmp/pids tmp/cache tmp/sockets tmp/storage storage public && \
    chown -R appuser:appuser log tmp storage public

# Switch to appuser
USER appuser

# Expose port
EXPOSE 3000

# Default command (puma is on PATH via GEM_HOME/bin)
CMD ["puma", "-C", "config/puma.rb"]
