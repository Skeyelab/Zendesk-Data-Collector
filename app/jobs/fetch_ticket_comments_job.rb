class FetchTicketCommentsJob < ApplicationJob
  include ZendeskRateLimitHandler

  queue_as :comments
  queue_with_priority 20 # Lower priority - process comments after incremental jobs

  def perform(ticket_id, desk_id, domain)
    desk = Desk.find(desk_id)
    ticket = ZendeskTicket.find_by(zendesk_id: ticket_id, domain: domain)

    unless ticket
      warning_msg = "[FetchTicketCommentsJob] Ticket #{ticket_id} not found for domain #{domain}, skipping"
      Rails.logger.warn warning_msg
      puts warning_msg
      return
    end

    # Check if desk is rate-limited (wait_till is in the future)
    current_time = Time.now.to_i
    if desk.wait_till && desk.wait_till > current_time
      wait_seconds = desk.wait_till - current_time
      wait_msg = "[FetchTicketCommentsJob] Desk #{desk.domain} is rate-limited, waiting #{wait_seconds}s (until #{Time.at(desk.wait_till)})"
      Rails.logger.info wait_msg
      puts wait_msg
      sleep(wait_seconds)
      desk.reload # Reload in case wait_till was updated
    end

    # Throttle: Add a small delay before making API call to avoid rate limits
    # This helps prevent hitting Zendesk's rate limits when many comment jobs run in parallel
    sleep_duration = ENV.fetch('COMMENT_JOB_DELAY_SECONDS', '0.5').to_f
    sleep(sleep_duration) if sleep_duration > 0

    client = ZendeskClientService.connect(desk)
    max_retries = 3
    retry_count = 0

    begin
      comments_msg = "[FetchTicketCommentsJob] Fetching comments for ticket #{ticket_id}"
      Rails.logger.debug comments_msg

      response = client.connection.get("/api/v2/tickets/#{ticket_id}/comments.json")

      # Monitor rate limit headers to track remaining requests
      rate_limit_info = log_rate_limit_headers(response.respond_to?(:env) ? response.env : response)

      # Dynamically adjust delay based on remaining rate limit
      if rate_limit_info && rate_limit_info[:percentage] < 20
        # If we're below 20% remaining, add extra delay to slow down
        extra_delay = (20 - rate_limit_info[:percentage]) * 0.1 # Up to 2 seconds extra delay
        sleep(extra_delay) if extra_delay > 0
      end

      # Check for 429 rate limit error in response
      # Handle both response.status and response.env[:status] for different response structures
      response_status = if response.respond_to?(:status)
                          response.status
                        elsif response.respond_to?(:env) && response.env && response.env[:status]
                          response.env[:status]
                        end

      if response_status == 429
        # For 429 responses, handle rate limiting
        # This will set wait_till and handle retry logic
        handle_rate_limit_error(response.respond_to?(:env) ? response.env : response, desk, ticket_id, retry_count,
                                max_retries)
        retry_count += 1
        raise 'Rate limit exceeded (429), retrying' if retry_count <= max_retries

        # Max retries reached, log and exit gracefully
        error_msg = "[FetchTicketCommentsJob] Max retries reached for ticket #{ticket_id}, skipping comments"
        Rails.logger.warn error_msg
        puts error_msg
        return

      end

      response_body = if response.body.is_a?(Hash)
                        response.body
                      else
                        JSON.parse(response.body)
                      end

      comments_data = response_body['comments'] || []

      if comments_data.any?
        # Update ticket's raw_data with comments
        updated_raw_data = ticket.raw_data.merge('comments' => comments_data)
        ticket.update_columns(raw_data: updated_raw_data)

        comments_count_msg = "[FetchTicketCommentsJob] Retrieved and stored #{comments_data.size} comment(s) for ticket #{ticket_id}"
        Rails.logger.debug comments_count_msg
      else
        no_comments_msg = "[FetchTicketCommentsJob] No comments found for ticket #{ticket_id}"
        Rails.logger.debug no_comments_msg
      end
    rescue StandardError => e
      # Check if it's a rate limit error (429) from Faraday
      is_rate_limit = e.message.include?('status 429') || e.message.include?('429') || e.message.include?('Rate limit exceeded')

      if is_rate_limit
        # Try to extract response from error, or use the error itself
        response_from_error = extract_response_from_error(e)
        handle_rate_limit_error(response_from_error || e, desk, ticket_id, retry_count, max_retries)
        retry_count += 1
        if retry_count <= max_retries
          retry
        else
          # Max retries reached, log and exit gracefully
          error_msg = "[FetchTicketCommentsJob] Max retries reached for ticket #{ticket_id} after rate limit, skipping comments"
          Rails.logger.warn error_msg
          puts error_msg
          return
        end
      end

      error_msg = "[FetchTicketCommentsJob] Error fetching comments for ticket #{ticket_id}: #{e.message}"
      Rails.logger.warn error_msg
      puts error_msg
      # Don't re-raise - let the job complete gracefully
    end
  end
end
