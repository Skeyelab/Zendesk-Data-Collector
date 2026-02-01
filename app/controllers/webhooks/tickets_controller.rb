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

      if domain.blank?
        return render json: {error: "domain is required"}, status: :unprocessable_entity
      end

      # Validate desk exists and is active before enqueueing
      desk = Desk.find_by(domain: domain, active: true)
      unless desk
        return render json: {error: "No active desk found for domain #{domain}"}, status: :not_found
      end

      unless %w[get put post].include?(method)
        return render json: {error: "method must be get, put, or post"}, status: :unprocessable_entity
      end

      if method != "post" && ticket_id.blank?
        return render json: {error: "ticket_id is required for get/put"}, status: :unprocessable_entity
      end

      ticket_id = ticket_id.to_i if ticket_id.present?
      ZendeskProxyJob.perform_later(domain.to_s, method, ticket_id, body)
      render json: {status: "accepted"}, status: :accepted
    end

    private

    def authenticate_webhook
      provided_secret = request.headers["X-Webhook-Secret"]
      expected_secret = ENV["WEBHOOKS_TICKETS_SECRET"]

      if expected_secret.blank?
        Rails.logger.error "[WebhooksTicketsController] WEBHOOKS_TICKETS_SECRET not configured"
        return render json: {error: "Webhook authentication not configured"}, status: :internal_server_error
      end

      if provided_secret.blank?
        return render json: {error: "X-Webhook-Secret header required"}, status: :unauthorized
      end

      # Use secure comparison to prevent timing attacks
      unless ActiveSupport::SecurityUtils.secure_compare(
        ::Digest::SHA256.hexdigest(provided_secret),
        ::Digest::SHA256.hexdigest(expected_secret)
      )
        return render json: {error: "Invalid webhook secret"}, status: :unauthorized
      end
    end

    def parse_payload
      return {} if request.raw_post.blank?

      JSON.parse(request.raw_post)
    rescue JSON::ParserError
      nil
    end
  end
end
