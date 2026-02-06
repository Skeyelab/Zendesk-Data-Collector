# frozen_string_literal: true

# Configuration constants for Zendesk API integration.
# These constants are used across jobs and services to maintain consistency.
module ZendeskConfig
  # Rate limit headroom percentage - back off when remaining quota drops below this
  # Default: 40% (Zendesk recommends leaving capacity for other API consumers)
  RATE_LIMIT_HEADROOM_PERCENT = ENV.fetch("ZENDESK_RATE_LIMIT_HEADROOM_PERCENT", "40").to_i

  # Time (seconds) to add after Retry-After when handling 429 responses
  # Ensures wait_till timestamp is in the future
  RATE_LIMIT_RESET_OFFSET = 1

  # Default stagger delay (seconds) between comment fetch jobs
  # Spreads API calls over time to avoid bursts
  COMMENT_JOB_STAGGER_SECONDS = ENV.fetch("COMMENT_JOB_STAGGER_SECONDS", "0.2").to_f

  # Default stagger delay (seconds) between metrics fetch jobs
  METRICS_JOB_STAGGER_SECONDS = ENV.fetch("METRICS_JOB_STAGGER_SECONDS", "0.2").to_f

  # Maximum cycle time (seconds) for stagger delay calculation
  # Jobs cycle back to 0 after this delay to avoid indefinite delays
  STAGGER_CYCLE_MAX_SECONDS = 5.0

  # Buffer time (seconds) before desk is considered ready for next sync
  # Prevents queuing jobs for desks that are nearly rate-limited
  DESK_READY_BUFFER_SECONDS = 300
end
