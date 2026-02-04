# frozen_string_literal: true

# Base class for jobs that fetch ticket details (metrics, comments) from Zendesk API.
# Subclasses implement template methods: api_path, response_key, resource_name, delay_env_var, persist_data.
class FetchTicketDetailJobBase < ApplicationJob
  include ZendeskRateLimitHandler

  MAX_RETRIES = 3

  def perform(ticket_id, desk_id, domain)
    desk = Desk.find(desk_id)
    ticket = ZendeskTicket.find_by(zendesk_id: ticket_id, domain: domain)

    unless ticket
      job_log(:warn, "[#{job_name}] Ticket #{ticket_id} not found for domain #{domain}, skipping")
      return
    end

    wait_if_rate_limited(desk)
    apply_throttle(ticket_id, desk)
    fetch_and_persist(ticket_id, desk_id, domain, desk, ticket)
  end

  private

  def job_name
    self.class.name
  end

  def apply_throttle(ticket_id, desk)
    sleep_duration = ENV.fetch(delay_env_var, "0").to_f
    return unless sleep_duration > 0

    job_log(:info,
      "[#{job_name}] Applying throttle delay: #{sleep_duration}s before API call for ticket #{ticket_id} (desk: #{desk.domain})")
    sleep(sleep_duration)
  end

  def fetch_and_persist(ticket_id, _desk_id, _domain, desk, ticket)
    client = ZendeskClientService.connect(desk)
    retry_count = 0

    begin
      job_log(:info,
        "[#{job_name}] Fetching #{resource_name} for ticket #{ticket_id} (desk: #{desk.domain}, retry: #{retry_count}/#{MAX_RETRIES})")

      response = client.connection.get(api_path(ticket_id))
      throttle_using_rate_limit_headers(response.respond_to?(:env) ? response.env : response)

      response_status = extract_response_status(response)
      if response_status == 429
        job_log(:warn, "[#{job_name}] ⚠️  Rate limit (429) received for ticket #{ticket_id} (desk: #{desk.domain})")
        env = response.respond_to?(:env) ? response.env : response
        handle_rate_limit_error(env, desk, ticket_id, retry_count, MAX_RETRIES)
        retry_count += 1

        if retry_count > MAX_RETRIES
          job_log(:warn,
            "[#{job_name}] ✗ Max retries reached for ticket #{ticket_id} (desk: #{desk.domain}), skipping #{resource_name}")
          return
        end

        job_log(:info, "[#{job_name}] Retrying ticket #{ticket_id} (attempt #{retry_count + 1}/#{MAX_RETRIES + 1})")
        raise "Rate limit exceeded (429), retrying"
      end

      response_body = parse_response_body(response)
      data = response_body[response_key] || empty_value

      if data.any?
        log_received(ticket_id, data)
        persist_data(ticket, data)
        job_log(:info,
          "[#{job_name}] ✓ Successfully stored #{resource_name} for ticket #{ticket_id} (desk: #{desk.domain})")
      else
        job_log(:info, "[#{job_name}] No #{resource_name} found for ticket #{ticket_id} (desk: #{desk.domain})")
      end
    rescue => e
      # Re-raise from 429 response path – we already handled it, just retry the begin block
      retry if e.message == "Rate limit exceeded (429), retrying"

      is_rate_limit = e.message.include?("status 429") || e.message.include?("429") || e.message.include?("Rate limit exceeded")

      if is_rate_limit
        job_log(:warn,
          "[#{job_name}] ⚠️  Rate limit error caught for ticket #{ticket_id} (desk: #{desk.domain}): #{e.message}")
        response_from_error = extract_response_from_error(e)
        handle_rate_limit_error(response_from_error || e, desk, ticket_id, retry_count, MAX_RETRIES)
        retry_count += 1

        if retry_count <= MAX_RETRIES
          job_log(:info,
            "[#{job_name}] Retrying ticket #{ticket_id} after rate limit (attempt #{retry_count + 1}/#{MAX_RETRIES + 1})")
          retry
        else
          job_log(:warn,
            "[#{job_name}] ✗ Max retries reached for ticket #{ticket_id} (desk: #{desk.domain}) after rate limit, skipping #{resource_name}")
          return
        end
      end

      job_log(:warn,
        "[#{job_name}] ✗ Error fetching #{resource_name} for ticket #{ticket_id} (desk: #{desk.domain}): #{e.class}: #{e.message}")
      Rails.logger.debug("[#{job_name}] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
    end
  end

  def log_received(ticket_id, data)
    # Override in subclass for custom received-data logging (e.g. metrics keys)
    count = data.is_a?(Array) ? data.size : data.keys.size
    job_log(:info, "[#{job_name}] Received #{count} #{resource_name} item(s) for ticket #{ticket_id}")
  end

  # Template methods - subclasses must implement
  def api_path(_ticket_id)
    raise NotImplementedError
  end

  def response_key
    raise NotImplementedError
  end

  def resource_name
    raise NotImplementedError
  end

  def delay_env_var
    raise NotImplementedError
  end

  def empty_value
    {}
  end

  def persist_data(_ticket, _data)
    raise NotImplementedError
  end
end
