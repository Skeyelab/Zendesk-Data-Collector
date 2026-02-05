# frozen_string_literal: true

# Unified proxy for n8n: forwards Zendesk API calls through our rate-limit queue. Does not create/update resource rows.
# Supports multiple resource types: tickets, users, etc.
module Webhooks
  class ZendeskController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [:create]
    before_action :authenticate_webhook, only: [:create]

    # Supported resource types and their configurations
    RESOURCE_CONFIGS = {
      "tickets" => {
        id_param: "ticket_id",
        body_wrapper: "ticket"
      },
      "users" => {
        id_param: "user_id",
        body_wrapper: "user"
      }
    }.freeze

    def create
      payload = (request.content_mime_type&.symbol == :json && params.present?) ? params.to_unsafe_h : parse_payload
      return render json: {error: "Invalid JSON"}, status: :unprocessable_entity unless payload.is_a?(Hash)

      # Extract common parameters
      domain = payload["domain"] || payload[:domain]
      method = (payload["method"] || payload[:method] || "get").to_s.downcase
      resource = (payload["resource"] || payload[:resource] || "").to_s.downcase
      body = payload["body"] || payload[:body]

      # Validate required parameters
      return render json: {error: "domain is required"}, status: :unprocessable_entity if domain.blank?
      return render json: {error: "resource is required (e.g., 'tickets', 'users')"}, status: :unprocessable_entity if resource.blank?

      # Validate resource type
      unless RESOURCE_CONFIGS.key?(resource)
        return render json: {error: "resource must be one of: #{RESOURCE_CONFIGS.keys.join(", ")}"}, status: :unprocessable_entity
      end

      # Validate desk exists and is active before enqueueing
      desk = Desk.find_by(domain: domain, active: true)
      return render json: {error: "No active desk found for domain #{domain}"}, status: :not_found unless desk

      # Validate HTTP method
      unless %w[get put post patch delete].include?(method)
        return render json: {error: "method must be get, put, post, patch, or delete"}, status: :unprocessable_entity
      end

      # Get resource configuration
      resource_config = RESOURCE_CONFIGS[resource]
      resource_id_param = resource_config[:id_param]
      body_wrapper = resource_config[:body_wrapper]

      # Extract resource ID (e.g., ticket_id or user_id)
      resource_id = payload[resource_id_param] || payload[resource_id_param.to_sym]

      # Validate body for write operations
      if %w[put post patch].include?(method) && body.blank?
        return render json: {error: "body is required for put/post/patch"}, status: :unprocessable_entity
      end

      # Validate resource ID for operations that need it
      if %w[get put patch delete].include?(method) && resource_id.blank?
        return render json: {error: "#{resource_id_param} is required for #{method}"}, status: :unprocessable_entity
      end

      resource_id = resource_id.to_i if resource_id.present?

      # Validate body structure for create/update operations
      if %w[put post patch].include?(method)
        unless valid_body_structure?(body, body_wrapper)
          return render json: {error: "body must contain a '#{body_wrapper}' object"}, status: :unprocessable_entity
        end
      end

      # GET operations are synchronous to return data immediately
      # DELETE operations should also be synchronous for confirmation
      if %w[get delete].include?(method)
        result = ZendeskProxyJob.perform_now(domain.to_s, method, resource, resource_id, body)
        if result
          render json: result[1], status: result[0]
        else
          render json: {error: "Proxy request failed"}, status: :service_unavailable
        end
      else
        # PUT, POST, PATCH are async to avoid blocking
        ZendeskProxyJob.perform_later(domain.to_s, method, resource, resource_id, body)
        render json: {status: "accepted", message: "Request queued for processing"}, status: :accepted
      end
    end

    private

    def authenticate_webhook
      provided_secret = request.headers["X-Webhook-Secret"]
      expected_secret = ENV["WEBHOOKS_ZENDESK_SECRET"] || ENV["WEBHOOKS_TICKETS_SECRET"]

      if expected_secret.blank?
        Rails.logger.error "[WebhooksZendeskController] WEBHOOKS_ZENDESK_SECRET not configured"
        return render json: {error: "Webhook authentication not configured"}, status: :internal_server_error
      end

      return render json: {error: "X-Webhook-Secret header required"}, status: :unauthorized if provided_secret.blank?

      # secure_compare already prevents timing attacks, no need to hash
      return if ActiveSupport::SecurityUtils.secure_compare(provided_secret, expected_secret)

      render json: {error: "Invalid webhook secret"}, status: :unauthorized
    end

    def parse_payload
      return {} if request.raw_post.blank?

      JSON.parse(request.raw_post)
    rescue JSON::ParserError
      nil
    end

    # Validate that the body has the expected structure for the resource
    # Per Zendesk API docs, requests must have the appropriate wrapper key (e.g., 'ticket', 'user')
    def valid_body_structure?(body, wrapper_key)
      return false unless body.is_a?(Hash)

      # Body should have the wrapper key with a hash value
      wrapper_data = body[wrapper_key] || body[wrapper_key.to_sym]
      wrapper_data.is_a?(Hash)
    end
  end
end
