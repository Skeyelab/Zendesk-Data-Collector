class IncrementalTicketJob < ApplicationJob
  queue_as :default

  def perform(desk_id)
    desk = Desk.find(desk_id)
    msg = "[IncrementalTicketJob] Starting for desk #{desk.domain} (ID: #{desk_id})"
    Rails.logger.info msg
    puts msg

    timestamp_msg = "[IncrementalTicketJob] Last timestamp: #{desk.last_timestamp} (#{Time.at(desk.last_timestamp) if desk.last_timestamp > 0})"
    Rails.logger.info timestamp_msg
    puts timestamp_msg

    client = ZendeskClientService.connect(desk)
    start_time = desk.last_timestamp

    begin
      fetch_msg = "[IncrementalTicketJob] Fetching tickets from Zendesk API (start_time: #{start_time})"
      Rails.logger.info fetch_msg
      puts fetch_msg

      tickets = client.tickets.incremental_export(start_time)

      ticket_count = tickets.respond_to?(:count) ? tickets.count : tickets.to_a.size
      received_msg = "[IncrementalTicketJob] Received #{ticket_count} ticket(s) from API"
      Rails.logger.info received_msg
      puts received_msg

      processed = 0
      created = 0
      updated = 0
      errors = 0

      tickets.each do |ticket_data|
        result = save_ticket_to_postgres(ticket_data, desk.domain)
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
        if processed % 10 == 0
          progress_msg = "[IncrementalTicketJob] Processed #{processed}/#{ticket_count} tickets (created: #{created}, updated: #{updated}, errors: #{errors})"
          Rails.logger.info progress_msg
          puts progress_msg
        end
      end

      summary_msg = "[IncrementalTicketJob] Completed processing: #{processed} total (created: #{created}, updated: #{updated}, errors: #{errors})"
      Rails.logger.info summary_msg
      puts summary_msg

      # Update desk timestamp if we got new data
      if tickets.respond_to?(:included) && tickets.included
        if tickets.included['end_time']
          new_timestamp = tickets.included['end_time']
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
      end
    rescue StandardError => e
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

  def save_ticket_to_postgres(ticket_data, domain)
    # Convert ticket data to hash if it's not already
    ticket_hash = ticket_data.is_a?(Hash) ? ticket_data : ticket_data.to_h

    # Ensure domain is set
    ticket_hash['domain'] = domain

    # Find or initialize ticket
    zendesk_id = ticket_hash['id'] || ticket_hash[:id]
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
  rescue StandardError => e
    error_msg = "[IncrementalTicketJob] Error saving ticket #{ticket_hash['id']} for #{domain}: #{e.message}"
    Rails.logger.error error_msg
    puts error_msg

    class_msg = "[IncrementalTicketJob] #{e.class}: #{e.message}"
    Rails.logger.error class_msg
    puts class_msg
    # Continue processing other tickets
    :error
  end
end
