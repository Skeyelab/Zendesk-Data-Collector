class IncrementalTicketJob < ApplicationJob
  queue_as :default

  def perform(desk_id)
    desk = Desk.find(desk_id)
    msg = "[IncrementalTicketJob] Starting for desk #{desk.domain} (ID: #{desk_id})"
    Rails.logger.info msg
    puts msg

    timestamp_msg = "[IncrementalTicketJob] Last timestamp: #{desk.last_timestamp} (#{if desk.last_timestamp > 0
                                                                                        Time.at(desk.last_timestamp)
                                                                                      end})"
    Rails.logger.info timestamp_msg
    puts timestamp_msg

    client = ZendeskClientService.connect(desk)
    start_time = desk.last_timestamp

    begin
      fetch_msg = "[IncrementalTicketJob] Fetching tickets from Zendesk API (start_time: #{start_time})"
      Rails.logger.info fetch_msg
      puts fetch_msg

      # Fetch tickets with sideloaded users
      response = client.connection.get("/api/v2/incremental/tickets.json") do |req|
        req.params[:start_time] = start_time
        req.params[:include] = "users"
      end

      # Handle response body (may be already parsed by JSON middleware or a string)
      response_body = if response.body.is_a?(Hash)
        response.body
      else
        JSON.parse(response.body)
      end

      tickets_data = response_body["tickets"] || []
      users_data = response_body["users"] || []
      end_time = response_body["end_time"]

      # Build user lookup map
      user_lookup = build_user_lookup(users_data)

      ticket_count = tickets_data.size
      received_msg = "[IncrementalTicketJob] Received #{ticket_count} ticket(s) and #{users_data.size} user(s) from API"
      Rails.logger.info received_msg
      puts received_msg

      processed = 0
      created = 0
      updated = 0
      errors = 0

      tickets_data.each do |ticket_data|
        # Enrich ticket with user data from sideloaded users
        enriched_ticket = enrich_ticket_with_users(ticket_data, user_lookup)

        # Fetch and add comments to the ticket
        enriched_ticket = fetch_ticket_comments(enriched_ticket, client, desk)

        result = save_ticket_to_postgres(enriched_ticket, desk.domain)
        processed += 1
        case result
        when :created
          created += 1
        when :updated
          updated += 1
        when :error
          errors += 1
        end

        # Log progress every 10 tickets
        next unless processed % 10 == 0

        progress_msg = "[IncrementalTicketJob] Processed #{processed}/#{ticket_count} tickets (created: #{created}, updated: #{updated}, errors: #{errors})"
        Rails.logger.info progress_msg
        puts progress_msg
      end

      summary_msg = "[IncrementalTicketJob] Completed processing: #{processed} total (created: #{created}, updated: #{updated}, errors: #{errors})"
      Rails.logger.info summary_msg
      puts summary_msg

      # Update desk timestamp if we got new data
      if end_time
        new_timestamp = end_time
        if new_timestamp > 0 && new_timestamp > start_time
          desk.last_timestamp = new_timestamp
          desk.save
          timestamp_update_msg = "[IncrementalTicketJob] Updated desk timestamp to #{new_timestamp} (#{Time.at(new_timestamp)})"
          Rails.logger.info timestamp_update_msg
          puts timestamp_update_msg
        else
          no_update_msg = "[IncrementalTicketJob] Timestamp not updated (new: #{new_timestamp}, start: #{start_time})"
          Rails.logger.info no_update_msg
          puts no_update_msg
        end
      end
    rescue => e
      error_msg = "[IncrementalTicketJob] Error processing tickets for desk #{desk_id}: #{e.message}"
      Rails.logger.error error_msg
      puts error_msg

      class_msg = "[IncrementalTicketJob] #{e.class}: #{e.message}"
      Rails.logger.error class_msg
      puts class_msg

      backtrace_msg = "[IncrementalTicketJob] Backtrace:\n#{e.backtrace.join("\n")}"
      Rails.logger.error backtrace_msg
      puts backtrace_msg
    ensure
      desk.queued = false
      desk.save
      complete_msg = "[IncrementalTicketJob] Job completed for desk #{desk.domain}, queued flag reset"
      Rails.logger.info complete_msg
      puts complete_msg
    end
  end

  private

  def fetch_ticket_comments(ticket_hash, client, desk)
    ticket_hash = ticket_hash.dup if ticket_hash.is_a?(Hash)
    ticket_id = ticket_hash["id"] || ticket_hash[:id]

    return ticket_hash unless ticket_id

    max_retries = 3
    retry_count = 0

    begin
      comments_msg = "[IncrementalTicketJob] Fetching comments for ticket #{ticket_id}"
      Rails.logger.debug comments_msg

      response = client.connection.get("/api/v2/tickets/#{ticket_id}/comments.json")

      # Check for 429 rate limit error in response
      if response.status == 429
        handle_rate_limit_error(response, desk, ticket_id, retry_count, max_retries)
        retry_count += 1
        raise "Rate limit exceeded (429)" if retry_count <= max_retries
      end

      response_body = if response.body.is_a?(Hash)
        response.body
      else
        JSON.parse(response.body)
      end

      comments_data = response_body["comments"] || []

      if comments_data.any?
        ticket_hash["comments"] = comments_data
        comments_count_msg = "[IncrementalTicketJob] Retrieved #{comments_data.size} comment(s) for ticket #{ticket_id}"
        Rails.logger.debug comments_count_msg
      end
    rescue => e
      # Check if it's a rate limit error (429) from Faraday
      is_rate_limit = e.message.include?("status 429") || e.message.include?("429")
      response = extract_response_from_error(e) if is_rate_limit

      if is_rate_limit
        handle_rate_limit_error(response, desk, ticket_id, retry_count, max_retries)
        retry_count += 1
        if retry_count <= max_retries
          retry
        end
      end

      error_msg = "[IncrementalTicketJob] Error fetching comments for ticket #{ticket_id}: #{e.message}"
      Rails.logger.warn error_msg
      puts error_msg
      # Continue without comments rather than failing the entire job
    end

    ticket_hash
  end

  def extract_response_from_error(error)
    # Faraday errors typically have a response method
    return error.response if error.respond_to?(:response) && error.response

    # Some errors might have response in @response instance variable
    return error.instance_variable_get(:@response) if error.instance_variable_defined?(:@response)

    # Check if error message indicates 429
    if error.message.include?("status 429")
      # Try to extract from env if available (ZendeskAPI callback style)
      return error.env if error.respond_to?(:env) && error.env
    end

    nil
  end

  def handle_rate_limit_error(response_or_env, desk, ticket_id, retry_count, max_retries)
    retry_after = extract_retry_after(response_or_env)
    # Use the Retry-After value directly from Zendesk, with minimal additional backoff
    wait_seconds = retry_after + retry_count # Small incremental backoff per retry

    # Update desk wait_till timestamp
    desk.wait_till = wait_seconds + Time.now.to_i
    begin
      desk.save!
    rescue => e
      Rails.logger.error("[IncrementalTicketJob] Failed to persist rate limit data for Desk ##{desk.id}: #{e.class}: #{e.message}")
    end

    rate_limit_msg = "[IncrementalTicketJob] Rate limit (429) for ticket #{ticket_id}, waiting #{wait_seconds}s (Retry-After: #{retry_after}s, retry #{retry_count + 1}/#{max_retries})"
    Rails.logger.warn rate_limit_msg
    puts rate_limit_msg

    # Wait before retrying
    sleep(wait_seconds)
  end

  def extract_retry_after(response_or_env)
    return 10 unless response_or_env

    # Handle Faraday response object (most common case)
    if response_or_env.respond_to?(:headers)
      headers = response_or_env.headers || {}
      # Try all possible header key formats
      retry_after_header = headers["retry-after"] || 
                          headers[:retry_after] || 
                          headers["Retry-After"] ||
                          headers[:Retry_After]
      if retry_after_header
        retry_after = retry_after_header.to_i
        return retry_after if retry_after > 0
      end
    end

    # Handle ZendeskAPI callback env hash (from ZendeskClientService)
    if response_or_env.is_a?(Hash)
      # Check response_headers in env hash
      if response_or_env[:response_headers]
        headers = response_or_env[:response_headers]
        retry_after_header = headers[:retry_after] || 
                            headers["retry-after"] ||
                            headers["Retry-After"] ||
                            headers[:Retry_After]
        if retry_after_header
          retry_after = retry_after_header.to_i
          return retry_after if retry_after > 0
        end
      end

      # Also check direct header access in env
      if response_or_env[:headers]
        headers = response_or_env[:headers]
        retry_after_header = headers["retry-after"] || 
                            headers[:retry_after] || 
                            headers["Retry-After"] ||
                            headers[:Retry_After]
        if retry_after_header
          retry_after = retry_after_header.to_i
          return retry_after if retry_after > 0
        end
      end
    end

    # Default to 10 seconds if Retry-After header not found
    Rails.logger.warn("[IncrementalTicketJob] Retry-After header not found, defaulting to 10 seconds")
    10
  end

  def build_user_lookup(users_data)
    return {} unless users_data.is_a?(Array)

    users_data.each_with_object({}) do |user, lookup|
      user_id = user.is_a?(Hash) ? (user["id"] || user[:id]) : user.id
      lookup[user_id] = user if user_id
    end
  end

  def enrich_ticket_with_users(ticket_hash, user_lookup)
    ticket_hash = ticket_hash.dup if ticket_hash.is_a?(Hash)

    # Add requester data
    if (req_id = ticket_hash["requester_id"] || ticket_hash[:requester_id]) && (requester = user_lookup[req_id])
      ticket_hash["requester"] = requester
    end

    # Add assignee data
    if (assignee_id = ticket_hash["assignee_id"] || ticket_hash[:assignee_id]) && (assignee = user_lookup[assignee_id])
      ticket_hash["assignee"] = assignee
    end

    ticket_hash
  end

  def save_ticket_to_postgres(ticket_data, domain)
    # Convert ticket data to hash if it's not already
    ticket_hash = ticket_data.is_a?(Hash) ? ticket_data : ticket_data.to_h

    # Ensure domain is set
    ticket_hash["domain"] = domain

    # Find or initialize ticket
    zendesk_id = ticket_hash["id"] || ticket_hash[:id]
    is_new = !ZendeskTicket.exists?(zendesk_id: zendesk_id, domain: domain)

    ticket = ZendeskTicket.find_or_initialize_by(
      zendesk_id: zendesk_id,
      domain: domain
    )

    # Use the model's assign_ticket_data method to handle field mapping
    ticket.assign_ticket_data(ticket_hash)

    ticket.save!

    # Return status for logging
    is_new ? :created : :updated
  rescue => e
    error_msg = "[IncrementalTicketJob] Error saving ticket #{ticket_hash["id"]} for #{domain}: #{e.message}"
    Rails.logger.error error_msg
    puts error_msg

    class_msg = "[IncrementalTicketJob] #{e.class}: #{e.message}"
    Rails.logger.error class_msg
    puts class_msg
    # Continue processing other tickets
    :error
  end
end
