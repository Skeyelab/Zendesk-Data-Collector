# frozen_string_literal: true

# Proxies a single Zendesk API call through our rate-limit queue. Does not write to ZendeskTicket.
class ZendeskProxyJob < ApplicationJob
  include ZendeskRateLimitHandler

  MAX_RETRIES = 3

  queue_as :proxy

  # method: "get" | "put" | "post"
  # ticket_id: required for get/put, nil for post (create)
  # body: hash for put/post request body (e.g. { ticket: { status: "solved" } })
  def perform(domain, method, ticket_id = nil, body = nil)
    desk = Desk.find_by(domain: domain)
    unless desk
      Rails.logger.warn "[ZendeskProxyJob] No desk found for domain #{domain}, skipping"
      return
    end

    unless desk.active?
      Rails.logger.warn "[ZendeskProxyJob] Desk #{desk.id} for domain #{domain} is inactive, skipping proxy request"
      return
    end

    wait_if_rate_limited(desk)
    client = ZendeskClientService.connect(desk)
    retry_count = 0

    path = build_path(method, ticket_id)

    begin
      response = send_request(client, method, path, body)
      throttle_using_rate_limit_headers(response.respond_to?(:env) ? response.env : response)

      status = extract_response_status(response)
      if status == 429
        handle_rate_limit_error(response.respond_to?(:env) ? response.env : response, desk, path, retry_count,
          MAX_RETRIES)
        retry_count += 1
        raise "Rate limit exceeded (429), retrying" if retry_count <= MAX_RETRIES

        return
      end

      # Proxy completed; we don't persist to ZendeskTicket
      Rails.logger.info "[ZendeskProxyJob] #{method.upcase} #{path} completed with status #{status}"
    rescue => e
      retry if e.message == "Rate limit exceeded (429), retrying"

      is_rate_limit = e.message.to_s.include?("429") || e.message.to_s.include?("Rate limit exceeded")
      if is_rate_limit && retry_count <= MAX_RETRIES
        response_from_error = extract_response_from_error(e)
        handle_rate_limit_error(response_from_error || e, desk, path, retry_count, MAX_RETRIES)
        retry_count += 1
        retry
      end
      raise
    end
  end

  private

  def build_path(method, ticket_id)
    case method.to_s.downcase
    when "post"
      "/api/v2/tickets.json"
    when "get", "put"
      raise ArgumentError, "ticket_id required for #{method}" if ticket_id.blank?

      "/api/v2/tickets/#{ticket_id}.json"
    else
      raise ArgumentError, "method must be get, put, or post"
    end
  end

  def send_request(client, method, path, body)
    payload = normalize_body(body)
    case method.to_s.downcase
    when "get"
      client.connection.get(path)
    when "put"
      client.connection.put(path, payload)
    when "post"
      client.connection.post(path, payload)
    else
      raise ArgumentError, "method must be get, put, or post"
    end
  end

  def normalize_body(body)
    return {} if body.nil?
    return body if body.is_a?(Hash)
    return JSON.parse(body) if body.is_a?(String)

    {}
  end
end
