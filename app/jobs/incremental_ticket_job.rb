class IncrementalTicketJob < ApplicationJob
  include ZendeskRateLimitHandler

  class RateLimitRetry < StandardError; end

  queue_as :incremental
  queue_with_priority 0 # Highest priority - process incremental jobs first

  def perform(desk_id)
    desk = Desk.find(desk_id)
    wait_if_rate_limited(desk)

    job_log(:info, "[IncrementalTicketJob] Starting for desk #{desk.domain} (ID: #{desk_id})")

    job_log(:info, "[IncrementalTicketJob] Last timestamp: #{desk.last_timestamp} (#{if desk.last_timestamp > 0
                                                                                       Time.at(desk.last_timestamp)
                                                                                     end})")

    client = ZendeskClientService.connect(desk)
    start_time = desk.last_timestamp
    max_retries = 3
    retry_count = 0

    begin
      job_log(:info,
        "[IncrementalTicketJob] Fetching tickets from Zendesk API (start_time: #{start_time}, retry: #{retry_count}/#{max_retries})")

      # Fetch tickets with sideloaded users
      response = client.connection.get("/api/v2/incremental/tickets.json") do |req|
        req.params[:start_time] = start_time
        req.params[:include] = "users"
      end

      # Monitor rate limit and back off when remaining is low (best practice: regulate request rate)
      throttle_using_rate_limit_headers(response.respond_to?(:env) ? response.env : response)

      # Handle 429: wait Retry-After then retry (best practice)
      response_status = extract_response_status(response)
      if response_status == 429
        handle_rate_limit_error(response.respond_to?(:env) ? response.env : response, desk, "incremental", retry_count,
          max_retries)
        retry_count += 1
        if retry_count <= max_retries
          job_log(:info, "[IncrementalTicketJob] Retrying after 429 (attempt #{retry_count}/#{max_retries})")
          raise RateLimitRetry
        end
        job_log(:warn, "[IncrementalTicketJob] Max retries reached after 429, exiting")
        return
      end

      # Handle response body (may be already parsed by JSON middleware or a string)
      response_body = parse_response_body(response)

      tickets_data = response_body["tickets"] || []
      users_data = response_body["users"] || []
      end_time = response_body["end_time"]

      # Build user lookup map
      user_lookup = build_user_lookup(users_data)

      ticket_count = tickets_data.size
      job_log(:info,
        "[IncrementalTicketJob] Received #{ticket_count} ticket(s) and #{users_data.size} user(s) from API")

      processed = 0
      created = 0
      updated = 0
      errors = 0

      tickets_data.each do |ticket_data|
        # Enrich ticket with user data from sideloaded users
        enriched_ticket = enrich_ticket_with_users(ticket_data, user_lookup)

        # Save ticket immediately (without comments)
        result = upsert_ticket(enriched_ticket, desk.domain)
        processed += 1
        case result
        when :created
          created += 1
        when :updated
          updated += 1
        when :error
          errors += 1
        end

        # Enqueue comment and metrics fetch jobs only for updates (new tickets don't have these yet)
        ticket_id = enriched_ticket["id"] || enriched_ticket[:id]
        if ticket_id && result == :updated
          status = enriched_ticket["status"] || enriched_ticket[:status]
          closed = %w[closed solved].include?(status.to_s)

          # Add a small delay to stagger jobs and reduce API call rate
          # Delay is based on ticket position to spread out execution over time
          stagger_seconds = ZendeskConfig::COMMENT_JOB_STAGGER_SECONDS
          delay_seconds = (processed * stagger_seconds) % ZendeskConfig::STAGGER_CYCLE_MAX_SECONDS

          # Enqueue comment job if fetch_comments is enabled
          if desk.fetch_comments
            comment_opts = {wait: delay_seconds.seconds}
            comment_opts[:queue] = "comments_closed" if closed
            FetchTicketCommentsJob.set(comment_opts).perform_later(ticket_id, desk.id, desk.domain)
          end

          # Enqueue metrics fetch job with a slight additional delay after comments
          # This ensures metrics jobs run after comments but still with proper staggering
          if desk.fetch_metrics
            metrics_stagger_seconds = ZendeskConfig::METRICS_JOB_STAGGER_SECONDS
            metrics_delay_seconds = delay_seconds + (processed * metrics_stagger_seconds) % ZendeskConfig::STAGGER_CYCLE_MAX_SECONDS
            metrics_opts = {wait: metrics_delay_seconds.seconds}
            metrics_opts[:queue] = "metrics_closed" if closed
            FetchTicketMetricsJob.set(metrics_opts).perform_later(ticket_id, desk.id, desk.domain)
          end
        end

        # Log progress every 10 tickets
        next unless processed % 10 == 0

        job_log(:info,
          "[IncrementalTicketJob] Processed #{processed}/#{ticket_count} tickets (created: #{created}, updated: #{updated}, errors: #{errors})")
      end

      job_log(:info,
        "[IncrementalTicketJob] Completed processing: #{processed} total (created: #{created}, updated: #{updated}, errors: #{errors})")

      # Update desk timestamp if we got new data
      if end_time
        new_timestamp = end_time
        if new_timestamp > 0 && new_timestamp > start_time
          desk.last_timestamp = new_timestamp
          desk.save
          job_log(:info,
            "[IncrementalTicketJob] Updated desk timestamp to #{new_timestamp} (#{Time.at(new_timestamp)})")
        else
          job_log(:info, "[IncrementalTicketJob] Timestamp not updated (new: #{new_timestamp}, start: #{start_time})")
        end
      end
    rescue RateLimitRetry
      retry
    rescue => e
      if rate_limit_error?(e)
        response_from_error = extract_response_from_error(e)
        handle_rate_limit_error(response_from_error || e, desk, "incremental", retry_count, max_retries)
        retry_count += 1
        if retry_count <= max_retries
          job_log(:info, "[IncrementalTicketJob] Retrying after 429 (attempt #{retry_count}/#{max_retries})")
          retry
        end
        job_log(:warn, "[IncrementalTicketJob] Max retries reached after 429, exiting")
        return
      end

      job_log_error(e, "desk #{desk_id}")
    ensure
      # Use update_all to set queued=false without affecting wait_till
      Desk.where(id: desk.id).update_all(queued: false)
      desk.reload
      job_log(:info, "[IncrementalTicketJob] Job completed for desk #{desk.domain}, queued flag reset")
    end
  end

  private

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

  def upsert_ticket(ticket_data, domain)
    ZendeskTicketUpsertService.call(ticket_data, domain)
  rescue => e
    job_log_error(e, "ticket #{ticket_data["id"] || ticket_data[:id]} for #{domain}")
    :error
  end
end
