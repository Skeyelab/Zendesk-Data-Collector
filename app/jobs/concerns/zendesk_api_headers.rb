# Shared header and Retry-After extraction for Zendesk API responses.
# Used by ZendeskRateLimitHandler (jobs) and ZendeskClientService (429 callback).
module ZendeskApiHeaders
  module_function

  def extract_headers(response_or_env)
    if response_or_env.respond_to?(:env) && response_or_env.env
      env = response_or_env.env
      return env[:response_headers] if env[:response_headers].present?
      return env[:headers] if env[:headers].present?
    end

    return response_or_env.headers if response_or_env.respond_to?(:headers) && response_or_env.headers.present?

    if response_or_env.is_a?(Hash)
      return response_or_env[:response_headers] if response_or_env[:response_headers]
      return response_or_env[:headers] if response_or_env[:headers]
    end

    nil
  end

  def extract_header_value(headers, possible_keys)
    return nil unless headers

    if headers.respond_to?(:get)
      possible_keys.each do |key|
        value = headers.get(key)
        return value if value
      end
    end

    if headers.is_a?(Hash) || headers.respond_to?(:[])
      possible_keys.each do |key|
        value = headers[key] || headers[key.to_s]
        return value if value

        symbol_key = key.underscore.to_sym
        value = headers[symbol_key] || headers[symbol_key.to_s]
        return value if value
      end
    end

    nil
  end

  # Returns Retry-After seconds from response/env; falls back to default_seconds (default 10).
  def extract_retry_after(response_or_env, default_seconds = 10)
    return default_seconds unless response_or_env

    if response_or_env.respond_to?(:response_headers) && response_or_env.response_headers
      retry_after = extract_header_value(response_or_env.response_headers, %w[Retry-After retry-after])
      return retry_after.to_i if retry_after.to_i.positive?
    end

    headers = extract_headers(response_or_env)
    if headers
      retry_after = extract_header_value(headers, %w[Retry-After retry-after])
      return retry_after.to_i if retry_after.to_i.positive?
    end

    default_seconds
  end
end
