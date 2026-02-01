module ZendeskRateLimitHandler
  extend ActiveSupport::Concern

  # Wait before making API requests if desk is in a rate-limit window.
  # See: https://developer.zendesk.com/documentation/api-basics/best-practices/best-practices-for-avoiding-rate-limiting/
  def wait_if_rate_limited(desk)
    current_time = Time.now.to_i
    return unless desk.wait_till && desk.wait_till > current_time

    wait_seconds = desk.wait_till - current_time
    Rails.logger.info "[#{self.class.name}] Desk #{desk.domain} rate-limited, waiting #{wait_seconds}s (until #{Time.at(desk.wait_till)})"
    sleep(wait_seconds) unless Rails.env.test?
    desk.reload
  end

  # When rate limit remaining is low, back off until reset to avoid 429.
  # Uses headroom threshold so we leave capacity for other API consumers (scripts, UI, integrations).
  # See: https://developer.zendesk.com/documentation/api-basics/best-practices/best-practices-for-avoiding-rate-limiting/
  def throttle_using_rate_limit_headers(response_or_env, job_name = self.class.name)
    info = log_rate_limit_headers(response_or_env, job_name)
    return unless info

    headroom_percent = ENV.fetch("ZENDESK_RATE_LIMIT_HEADROOM_PERCENT", "20").to_i
    return unless info[:percentage] && info[:percentage] < headroom_percent
    return unless info[:reset]&.positive?

    wait_seconds = info[:reset] + 1
    Rails.logger.info "[#{job_name}] Rate limit low (#{info[:percentage]}% remaining, headroom #{headroom_percent}%), backing off #{wait_seconds}s until reset"
    sleep(wait_seconds) unless Rails.env.test?
  end

  private

  # Extract and log rate limit information from response headers
  # See: https://developer.zendesk.com/api-reference/introduction/rate-limits/
  def log_rate_limit_headers(response_or_env, job_name = self.class.name)
    return unless response_or_env

    headers = extract_headers(response_or_env)
    return unless headers

    # Standard rate limit headers
    rate_limit = extract_header_value(headers, %w[X-Rate-Limit x-rate-limit ratelimit-limit])
    rate_limit_remaining = extract_header_value(headers,
      %w[X-Rate-Limit-Remaining x-rate-limit-remaining ratelimit-remaining])
    rate_limit_reset = extract_header_value(headers, ["ratelimit-reset"])

    return unless rate_limit && rate_limit_remaining

    rate_limit = rate_limit.to_i
    rate_limit_remaining = rate_limit_remaining.to_i
    percentage_remaining = (rate_limit_remaining.to_f / rate_limit.to_f * 100).round(1)

    # Log rate limit status (X-Rate-Limit, X-Rate-Limit-Remaining per Zendesk API docs)
    rate_limit_msg = "[#{job_name}] X-Rate-Limit: #{rate_limit}, X-Rate-Limit-Remaining: #{rate_limit_remaining} (#{percentage_remaining}%)"
    rate_limit_msg += " (resets in #{rate_limit_reset}s)" if rate_limit_reset

    headroom_percent = ENV.fetch("ZENDESK_RATE_LIMIT_HEADROOM_PERCENT", "20").to_i
    # Warn if we're getting low on requests (below half of headroom)
    if percentage_remaining < (headroom_percent / 2)
      Rails.logger.warn rate_limit_msg
    else
      Rails.logger.info rate_limit_msg
    end
    puts rate_limit_msg

    # Return rate limit info for potential dynamic throttling
    {
      limit: rate_limit,
      remaining: rate_limit_remaining,
      reset: rate_limit_reset&.to_i,
      percentage: percentage_remaining
    }
  end

  def extract_headers(response_or_env)
    # Try accessing response.env (Faraday stores response data in env)
    if response_or_env.respond_to?(:env) && response_or_env.env
      env = response_or_env.env
      return env[:response_headers] if env[:response_headers].present?
      return env[:headers] if env[:headers].present?
    end

    # Handle Faraday response object headers (e.g. from WebMock)
    return response_or_env.headers if response_or_env.respond_to?(:headers) && response_or_env.headers.present?

    # Handle ZendeskAPI callback env hash
    if response_or_env.is_a?(Hash)
      return response_or_env[:response_headers] if response_or_env[:response_headers]
      return response_or_env[:headers] if response_or_env[:headers]
    end

    nil
  end

  def extract_header_value(headers, possible_keys)
    return nil unless headers

    # Try accessing via get method first (Faraday::Utils::Headers supports this, case-insensitive)
    if headers.respond_to?(:get)
      possible_keys.each do |key|
        value = headers.get(key)
        return value if value
      end
    end

    # Try direct hash access with various key formats
    if headers.is_a?(Hash) || headers.respond_to?(:[])
      possible_keys.each do |key|
        # Try string key
        value = headers[key] || headers[key.to_s]
        return value if value

        # Try symbol key
        symbol_key = key.underscore.to_sym
        value = headers[symbol_key] || headers[symbol_key.to_s]
        return value if value
      end
    end

    nil
  end

  def extract_response_from_error(error)
    # Faraday errors typically have a response method
    return error.response if error.respond_to?(:response) && error.response

    # Some errors might have response in @response instance variable
    return error.instance_variable_get(:@response) if error.instance_variable_defined?(:@response)

    # Check if error message indicates 429
    if error.message.include?("status 429")
      # Try to extract from env if available (ZendeskAPI callback style)
      return error.env if error.respond_to?(:env) && error.env

      # For WebMock/Faraday, try to get response from exception's internal state
      # Faraday::ClientError and similar exceptions may have @response or @env
      if error.instance_variable_defined?(:@response)
        response = error.instance_variable_get(:@response)
        return response if response
      end

      if error.instance_variable_defined?(:@env)
        env = error.instance_variable_get(:@env)
        return env if env
      end
    end

    nil
  end

  def handle_rate_limit_error(response_or_env, desk, resource_id, retry_count, max_retries)
    retry_after = extract_retry_after(response_or_env)
    # Use the Retry-After value directly from Zendesk, with minimal additional backoff
    wait_seconds = retry_after + retry_count # Small incremental backoff per retry

    # Ensure wait_seconds is at least 1 to guarantee wait_till is in the future
    wait_seconds = [wait_seconds, 1].max

    # Update desk wait_till timestamp - recalculate current_time right before update to ensure it's in the future
    new_wait_till = wait_seconds + Time.now.to_i

    # Always update wait_till - use update_all to ensure it's persisted even if there are validation issues
    Desk.where(id: desk.id).update_all(wait_till: new_wait_till)
    desk.reload

    rate_limit_msg = "[#{self.class.name}] Rate limit (429) for resource #{resource_id}, waiting #{wait_seconds}s (Retry-After: #{retry_after}s, retry #{retry_count + 1}/#{max_retries})"
    Rails.logger.warn rate_limit_msg
    puts rate_limit_msg

    # Wait before retrying
    sleep(wait_seconds) unless Rails.env.test?
  end

  def extract_retry_after(response_or_env)
    return 10 unless response_or_env

    # Faraday::TooManyRequestsError (and other Faraday::Error subclasses) have response_headers method
    if response_or_env.respond_to?(:response_headers) && response_or_env.response_headers
      retry_after = extract_header_value(response_or_env.response_headers, %w[Retry-After retry-after])
      return retry_after.to_i if retry_after.to_i.positive?
    end

    headers = extract_headers(response_or_env)
    if headers
      retry_after = extract_header_value(headers, %w[Retry-After retry-after])
      return retry_after.to_i if retry_after.to_i.positive?
    end

    Rails.logger.debug("[#{self.class.name}] Retry-After header not found, defaulting to 10 seconds")
    10
  end
end
