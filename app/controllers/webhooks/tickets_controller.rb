# frozen_string_literal: true

# Queued proxy for n8n: forwards Zendesk API calls through our rate-limit queue. Does not create/update ZendeskTicket rows.
module Webhooks
  class TicketsController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [:create]
    before_action :authenticate_webhook, only: [:create]

    def create
      payload = (request.content_mime_type&.symbol == :json && params.present?) ? params.to_unsafe_h : parse_payload
      return render json: {error: "Invalid JSON"}, status: :unprocessable_entity unless payload.is_a?(Hash)

      domain = payload["domain"] || payload[:domain]
      method = (payload["method"] || payload[:method] || "get").to_s.downcase
      ticket_id = payload["ticket_id"] || payload[:ticket_id]
      body = payload["body"] || payload[:body]

      return render json: {error: "domain is required"}, status: :unprocessable_entity if domain.blank?

      # Validate desk exists and is active before enqueueing
      desk = Desk.find_by(domain: domain, active: true)
      return render json: {error: "No active desk found for domain #{domain}"}, status: :not_found unless desk

      # PATCH is the recommended method for partial updates per Zendesk API docs
      # PUT replaces the entire resource, PATCH updates specific fields
      unless %w[get put post patch delete].include?(method)
        return render json: {error: "method must be get, put, post, patch, or delete"}, status: :unprocessable_entity
      end

      if %w[put post patch].include?(method) && body.blank?
        return render json: {error: "body is required for put/post/patch"}, status: :unprocessable_entity
      end

      if %w[get put patch delete].include?(method) && ticket_id.blank?
        return render json: {error: "ticket_id is required for #{method}"}, status: :unprocessable_entity
      end

      ticket_id = ticket_id.to_i if ticket_id.present?

      # Validate ticket body structure for create/update operations
      if %w[put post patch].include?(method)
        unless valid_ticket_body?(body)
          return render json: {error: "body must contain a 'ticket' object"}, status: :unprocessable_entity
        end
      end

      # GET operations are synchronous to return data immediately
      # DELETE operations should also be synchronous for confirmation
      if %w[get delete].include?(method)
        result = ZendeskProxyJob.perform_now(domain.to_s, method, ticket_id, body)
        if result
          render json: result[1], status: result[0]
        else
          render json: {error: "Proxy request failed"}, status: :service_unavailable
        end
      else
        # PUT, POST, PATCH are async to avoid blocking
        ZendeskProxyJob.perform_later(domain.to_s, method, ticket_id, body)
        render json: {status: "accepted", message: "Request queued for processing"}, status: :accepted
      end
    end

    private

    def authenticate_webhook
      provided_secret = request.headers["X-Webhook-Secret"]
      expected_secret = ENV["WEBHOOKS_TICKETS_SECRET"]

      if expected_secret.blank?
        Rails.logger.error "[WebhooksTicketsController] WEBHOOKS_TICKETS_SECRET not configured"
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

    # Validate that the body has the expected structure for ticket operations
    # Per Zendesk API docs, ticket create/update requests must have a 'ticket' key
    def valid_ticket_body?(body)
      return false unless body.is_a?(Hash)

      # Body should have a 'ticket' key with a hash value
      ticket_data = body["ticket"] || body[:ticket]
      ticket_data.is_a?(Hash)
    end
  end
end
