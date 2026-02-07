# frozen_string_literal: true

# Proxies a single Zendesk API call through our rate-limit queue. Does not write to ZendeskTicket.
class ZendeskProxyJob < ApplicationJob
  include ZendeskRateLimitHandler

  MAX_RETRIES = 3

  queue_as :proxy

  # method: "get" | "put" | "post" | "patch" | "delete"
  # resource_type: "tickets" | "users"
  # resource_id: required for get/put/patch/delete, nil for post (create)
  # body: hash for put/post/patch request body (e.g. { ticket: { status: "solved" } } or { user: { name: "John" } })
  def perform(domain, method, resource_type = "tickets", resource_id = nil, body = nil)
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

    path = build_path(method, resource_type, resource_id)

    begin
      response = send_request(client, method, path, body)
      throttle_using_rate_limit_headers(response.respond_to?(:env) ? response.env : response)

      status = extract_response_status(response)
      if status == 429
        handle_rate_limit_error(response.respond_to?(:env) ? response.env : response, desk, path, retry_count,
          MAX_RETRIES)
        retry_count += 1
        raise "Rate limit exceeded (429), retrying" if retry_count <= MAX_RETRIES

        Rails.logger.warn "[ZendeskProxyJob] Max retries reached for #{method.upcase} #{path} after rate limit"
        return [429, {error: "Rate limit exceeded, max retries reached"}] if synchronous_method?(method)
        return
      end

      # Log successful operations with details
      response_body = parse_response_body(response)
      Rails.logger.info "[ZendeskProxyJob] #{method.upcase} #{path} completed with status #{status} (desk: #{desk.domain})"

      # Return response for GET and DELETE operations
      [status, response_body] if synchronous_method?(method)
    rescue => e
      retry if e.message == "Rate limit exceeded (429), retrying"

      if rate_limit_error?(e) && retry_count <= MAX_RETRIES
        response_from_error = extract_response_from_error(e)
        handle_rate_limit_error(response_from_error || e, desk, path, retry_count, MAX_RETRIES)
        retry_count += 1
        retry
      end

      # RecordInvalid (422/413) is a validation response (e.g. duplicate email), not a server error
      if duplicate_value_validation_error?(e)
        validation_msg = validation_error_message(e)
        Rails.logger.warn "[ZendeskProxyJob] Validation: #{method.upcase} #{path} - #{validation_msg}"
        return [422, {error: validation_msg, error_class: e.class.name}] if synchronous_method?(method)
        return
      end

      # Log detailed error information
      Rails.logger.error "[ZendeskProxyJob] Error in #{method.upcase} #{path}: #{e.class.name} - #{e.message}"
      Rails.logger.error "[ZendeskProxyJob] Backtrace: #{e.backtrace.first(5).join("\n")}"

      # For synchronous operations, return error details
      if synchronous_method?(method)
        error_status = extract_error_status(e) || 500
        error_body = {
          error: e.message,
          error_class: e.class.name
        }
        return [error_status, error_body]
      end

      raise
    end
  end

  private

  # RecordInvalid covers 422/413 validation failures (e.g. duplicate email). Treat as expected validation response.
  def duplicate_value_validation_error?(error)
    error.class.name.include?("RecordInvalid")
  end

  def validation_error_message(error)
    return error.errors.to_s if error.respond_to?(:errors) && error.errors.present?
    if error.respond_to?(:response) && error.response.is_a?(Hash) && error.response[:body].present?
      return error.response[:body].to_s
    end
    error.message.to_s
  end

  # Check if the method is synchronous (returns response immediately)
  def synchronous_method?(method)
    %w[get delete].include?(method.to_s.downcase)
  end

  # HTTP status code mapping for error messages
  ERROR_STATUS_MAP = {
    "Not Found" => 404,
    "Forbidden" => 403,
    "Unauthorized" => 401,
    "Unprocessable" => 422
  }.freeze

  # Extract HTTP status from error when available
  def extract_error_status(error)
    if error.respond_to?(:response) && error.response.respond_to?(:status)
      return error.response.status
    end

    # Try to extract from Faraday error env
    if error.respond_to?(:response) && error.response.is_a?(Hash)
      return error.response[:status] if error.response[:status]
    end

    # Check message for status codes using predefined mapping
    ERROR_STATUS_MAP.each do |pattern, status|
      return status if error.message.include?(pattern)
    end

    nil
  end

  def build_path(method, resource_type, resource_id)
    # Normalize resource_type to plural form
    resource_path = case resource_type.to_s.downcase
    when "tickets", "ticket"
      "tickets"
    when "users", "user"
      "users"
    else
      raise ArgumentError, "resource_type must be tickets or users"
    end

    case method.to_s.downcase
    when "post"
      "/api/v2/#{resource_path}.json"
    when "get", "put", "patch", "delete"
      raise ArgumentError, "resource_id required for #{method}" if resource_id.blank?

      "/api/v2/#{resource_path}/#{resource_id}.json"
    else
      raise ArgumentError, "method must be get, put, post, patch, or delete"
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
    when "patch"
      # PATCH is recommended by Zendesk for partial updates
      client.connection.patch(path, payload)
    when "delete"
      client.connection.delete(path)
    else
      raise ArgumentError, "method must be get, put, post, patch, or delete"
    end
  end

  def normalize_body(body)
    return {} if body.nil?
    return body if body.is_a?(Hash)

    # Handle JSON string
    if body.is_a?(String)
      begin
        return JSON.parse(body)
      rescue JSON::ParserError => e
        Rails.logger.warn "[ZendeskProxyJob] Failed to parse body as JSON: #{e.message}"
        return {}
      end
    end

    {}
  end
end
