# frozen_string_literal: true

# Queued proxy for n8n: forwards Zendesk API calls through our rate-limit queue. Does not create/update ZendeskTicket rows.
module Webhooks
  class TicketsController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [:create]

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

    def parse_payload
      return {} if request.raw_post.blank?

      JSON.parse(request.raw_post)
    rescue JSON::ParserError
      nil
    end
  end
end
