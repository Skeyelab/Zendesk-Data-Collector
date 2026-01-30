class FetchTicketMetricsJob < ApplicationJob
  include ZendeskRateLimitHandler

  queue_as :metrics
  queue_with_priority 10 # Higher priority than comments - process metrics after incremental jobs

  def perform(ticket_id, desk_id, domain)
    desk = Desk.find(desk_id)
    ticket = ZendeskTicket.find_by(zendesk_id: ticket_id, domain: domain)

    unless ticket
      warning_msg = "[FetchTicketMetricsJob] Ticket #{ticket_id} not found for domain #{domain}, skipping"
      Rails.logger.warn warning_msg
      puts warning_msg
      return
    end

    wait_if_rate_limited(desk)

    # Throttle: Add a small delay before making API call to avoid rate limits
    # This helps prevent hitting Zendesk's rate limits when many metrics jobs run in parallel
    sleep_duration = ENV.fetch("METRICS_JOB_DELAY_SECONDS", "0.5").to_f
    if sleep_duration > 0
      throttle_msg = "[FetchTicketMetricsJob] Applying throttle delay: #{sleep_duration}s before API call for ticket #{ticket_id} (desk: #{desk.domain})"
      Rails.logger.info throttle_msg
      puts throttle_msg
      sleep(sleep_duration)
    end

    client = ZendeskClientService.connect(desk)
    max_retries = 3
    retry_count = 0

    begin
      metrics_msg = "[FetchTicketMetricsJob] Fetching metrics for ticket #{ticket_id} (desk: #{desk.domain}, retry: #{retry_count}/#{max_retries})"
      Rails.logger.info metrics_msg
      puts metrics_msg

      response = client.connection.get("/api/v2/tickets/#{ticket_id}/metrics.json")

      # Monitor rate limit and back off when remaining is low (best practice: regulate request rate)
      throttle_using_rate_limit_headers(response.respond_to?(:env) ? response.env : response)

      # Check for 429 rate limit error in response
      # Handle both response.status and response.env[:status] for different response structures
      response_status = if response.respond_to?(:status)
        response.status
      elsif response.respond_to?(:env) && response.env && response.env[:status]
        response.env[:status]
      end

      if response_status == 429
        # For 429 responses, handle rate limiting
        rate_limit_msg = "[FetchTicketMetricsJob] ⚠️  Rate limit (429) received for ticket #{ticket_id} (desk: #{desk.domain})"
        Rails.logger.warn rate_limit_msg
        puts rate_limit_msg

        # This will set wait_till and handle retry logic
        handle_rate_limit_error(response.respond_to?(:env) ? response.env : response, desk, ticket_id, retry_count,
          max_retries)
        retry_count += 1
        if retry_count <= max_retries
          retry_msg = "[FetchTicketMetricsJob] Retrying ticket #{ticket_id} (attempt #{retry_count + 1}/#{max_retries + 1})"
          Rails.logger.info retry_msg
          puts retry_msg
          raise "Rate limit exceeded (429), retrying"
        else
          # Max retries reached, log and exit gracefully
          error_msg = "[FetchTicketMetricsJob] ✗ Max retries reached for ticket #{ticket_id} (desk: #{desk.domain}), skipping metrics"
          Rails.logger.warn error_msg
          puts error_msg
          return
        end
      end

      response_body = if response.body.is_a?(Hash)
        response.body
      else
        JSON.parse(response.body)
      end

      metrics_data = response_body["ticket_metric"] || {}

      if metrics_data.any?
        # Log what metrics we received
        metrics_keys = metrics_data.keys.join(", ")
        received_msg = "[FetchTicketMetricsJob] Received metrics data for ticket #{ticket_id}: #{metrics_keys}"
        Rails.logger.info received_msg
        puts received_msg

        # Update ticket with metrics data (extracts to columns and stores in raw_data)
        ticket.assign_metrics_data(metrics_data)

        # Log key metrics that were extracted
        extracted_metrics = []
        if ticket.first_reply_time_in_minutes
          extracted_metrics << "first_reply_time: #{ticket.first_reply_time_in_minutes}min"
        end
        if ticket.first_resolution_time_in_minutes
          extracted_metrics << "first_resolution_time: #{ticket.first_resolution_time_in_minutes}min"
        end
        if ticket.full_resolution_time_in_minutes
          extracted_metrics << "full_resolution_time: #{ticket.full_resolution_time_in_minutes}min"
        end
        extracted_metrics << "reopens: #{ticket.reopens}" if ticket.reopens
        extracted_metrics << "replies: #{ticket.replies}" if ticket.replies
        if extracted_metrics.any?
          extracted_msg = "[FetchTicketMetricsJob] Extracted metrics for ticket #{ticket_id}: #{extracted_metrics.join(", ")}"
          Rails.logger.info extracted_msg
          puts extracted_msg
        end

        # Save the ticket with all updates
        ticket.save!

        success_msg = "[FetchTicketMetricsJob] ✓ Successfully stored metrics for ticket #{ticket_id} (desk: #{desk.domain})"
        Rails.logger.info success_msg
        puts success_msg
      else
        no_metrics_msg = "[FetchTicketMetricsJob] No metrics found in response for ticket #{ticket_id} (desk: #{desk.domain})"
        Rails.logger.info no_metrics_msg
        puts no_metrics_msg
      end
    rescue => e
      # Check if it's a rate limit error (429) from Faraday
      is_rate_limit = e.message.include?("status 429") || e.message.include?("429") || e.message.include?("Rate limit exceeded")

      if is_rate_limit
        rate_limit_error_msg = "[FetchTicketMetricsJob] ⚠️  Rate limit error caught for ticket #{ticket_id} (desk: #{desk.domain}): #{e.message}"
        Rails.logger.warn rate_limit_error_msg
        puts rate_limit_error_msg

        # Try to extract response from error, or use the error itself
        response_from_error = extract_response_from_error(e)
        handle_rate_limit_error(response_from_error || e, desk, ticket_id, retry_count, max_retries)
        retry_count += 1
        if retry_count <= max_retries
          retry_msg = "[FetchTicketMetricsJob] Retrying ticket #{ticket_id} after rate limit (attempt #{retry_count + 1}/#{max_retries + 1})"
          Rails.logger.info retry_msg
          puts retry_msg
          retry
        else
          # Max retries reached, log and exit gracefully
          error_msg = "[FetchTicketMetricsJob] ✗ Max retries reached for ticket #{ticket_id} (desk: #{desk.domain}) after rate limit, skipping metrics"
          Rails.logger.warn error_msg
          puts error_msg
          return
        end
      end

      error_msg = "[FetchTicketMetricsJob] ✗ Error fetching metrics for ticket #{ticket_id} (desk: #{desk.domain}): #{e.class}: #{e.message}"
      Rails.logger.warn error_msg
      puts error_msg
      if e.backtrace
        backtrace_msg = "[FetchTicketMetricsJob] Backtrace: #{e.backtrace.first(3).join("\n")}"
        Rails.logger.debug backtrace_msg
      end
      # Don't re-raise - let the job complete gracefully
    end
  end
end
