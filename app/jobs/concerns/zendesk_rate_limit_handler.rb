module ZendeskRateLimitHandler
  extend ActiveSupport::Concern

  # Wait before making API requests if desk is in a rate-limit window.
  # See: https://developer.zendesk.com/documentation/api-basics/best-practices/best-practices-for-avoiding-rate-limiting/
  def wait_if_rate_limited(desk)
    current_time = Time.now.to_i
    return unless desk.wait_till && desk.wait_till > current_time

    wait_seconds = desk.wait_till - current_time
    Rails.logger.info "[#{self.class.name}] Desk #{desk.domain} rate-limited, waiting #{wait_seconds}s (until #{Time.at(desk.wait_till)})"
    sleep(wait_seconds)
    desk.reload
  end

  # When rate limit remaining is low, back off until reset to avoid 429.
  # See: https://developer.zendesk.com/documentation/api-basics/best-practices/best-practices-for-avoiding-rate-limiting/
  def throttle_using_rate_limit_headers(response_or_env, job_name = self.class.name)
    info = log_rate_limit_headers(response_or_env, job_name)
    return unless info
    return unless info[:percentage] && info[:percentage] < 20
    return unless info[:reset]&.positive?

    wait_seconds = info[:reset] + 1
    Rails.logger.info "[#{job_name}] Rate limit low (#{info[:percentage]}% remaining), backing off #{wait_seconds}s until reset"
    sleep(wait_seconds)
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

    # Log rate limit status
    rate_limit_msg = "[#{job_name}] Rate limit: #{rate_limit_remaining}/#{rate_limit} remaining (#{percentage_remaining}%)"
    rate_limit_msg += " (resets in #{rate_limit_reset}s)" if rate_limit_reset

    # Warn if we're getting low on requests
    if percentage_remaining < 10
      Rails.logger.warn rate_limit_msg
      puts rate_limit_msg
    elsif percentage_remaining < 25
      Rails.logger.info rate_limit_msg
    else
      Rails.logger.debug rate_limit_msg
    end

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
    sleep(wait_seconds)
  end

  def extract_retry_after(response_or_env)
    return 10 unless response_or_env

    # Try to get headers from various possible locations
    headers = nil

    # First, try accessing response.env (Faraday stores response data in env)
    if response_or_env.respond_to?(:env) && response_or_env.env
      env = response_or_env.env
      # Check response_headers in env hash (Faraday's standard location)
      if env[:response_headers]
        headers = env[:response_headers]
        # Try all possible header key formats (case-insensitive)
        retry_after_header = headers["Retry-After"] ||
          headers[:Retry_After] ||
          headers["retry-after"] ||
          headers[:retry_after] ||
          headers["RETRY-AFTER"] ||
          headers[:RETRY_AFTER]
        if retry_after_header
          retry_after = retry_after_header.to_i
          return retry_after if retry_after > 0
        end
      end
      # Also check headers directly in env
      if env[:headers]
        headers = env[:headers]
        retry_after_header = headers["Retry-After"] ||
          headers[:Retry_After] ||
          headers["retry-after"] ||
          headers[:retry_after]
        if retry_after_header
          retry_after = retry_after_header.to_i
          return retry_after if retry_after > 0
        end
      end
    end

    # Handle Faraday response object headers (most common case)
    if response_or_env.respond_to?(:headers)
      headers = response_or_env.headers || {}

      # Try accessing via get method first (Faraday::Utils::Headers supports this, case-insensitive)
      if headers.respond_to?(:get)
        retry_after_header = headers.get("Retry-After") ||
          headers.get("retry-after") ||
          headers.get(:retry_after)
        if retry_after_header
          retry_after = retry_after_header.to_i
          return retry_after if retry_after > 0
        end
      end

      # Try direct hash access with various key formats
      if headers.is_a?(Hash) || headers.respond_to?(:[])
        retry_after_header = headers["Retry-After"] ||
          headers[:Retry_After] ||
          headers["retry-after"] ||
          headers[:retry_after] ||
          headers["RETRY-AFTER"] ||
          headers[:RETRY_AFTER]
        if retry_after_header
          retry_after = retry_after_header.to_i
          return retry_after if retry_after > 0
        end
      end
    end

    # Handle ZendeskAPI callback env hash (from ZendeskClientService)
    if response_or_env.is_a?(Hash)
      # Check response_headers in env hash
      if response_or_env[:response_headers]
        headers = response_or_env[:response_headers]
        retry_after_header = headers[:retry_after] ||
          headers["retry-after"] ||
          headers["Retry-After"] ||
          headers[:Retry_After]
        if retry_after_header
          retry_after = retry_after_header.to_i
          return retry_after if retry_after > 0
        end
      end

      # Also check direct header access in env
      if response_or_env[:headers]
        headers = response_or_env[:headers]
        retry_after_header = headers["retry-after"] ||
          headers[:retry_after] ||
          headers["Retry-After"] ||
          headers[:Retry_After]
        if retry_after_header
          retry_after = retry_after_header.to_i
          return retry_after if retry_after > 0
        end
      end
    end

    # Default to 10 seconds if Retry-After header not found
    Rails.logger.warn("[#{self.class.name}] Retry-After header not found, defaulting to 10 seconds")
    10
  end
end
