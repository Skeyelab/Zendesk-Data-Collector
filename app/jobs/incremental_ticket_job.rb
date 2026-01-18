class IncrementalTicketJob < ApplicationJob
  queue_as :default

  def perform(desk_id)
    desk = Desk.find(desk_id)
    client = ZendeskClientService.connect(desk)
    start_time = desk.last_timestamp

    begin
      tickets = client.tickets.incremental_export(start_time)

      tickets.each do |ticket_data|
        save_ticket_to_mongodb(ticket_data, desk.domain)
      end

      # Update desk timestamp if we got new data
      if tickets.respond_to?(:included) && tickets.included
        if tickets.included['end_time']
          new_timestamp = tickets.included['end_time']
          if new_timestamp > 0 && new_timestamp > start_time
            desk.last_timestamp = new_timestamp
            desk.save
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Error processing tickets for desk #{desk_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    ensure
      desk.queued = false
      desk.save
    end
  end

  private

  def save_ticket_to_mongodb(ticket_data, domain)
    # Convert ticket data to hash if it's not already
    ticket_hash = ticket_data.is_a?(Hash) ? ticket_data : ticket_data.to_h

    # Ensure domain is set
    ticket_hash['domain'] = domain

    # Find or initialize ticket
    zendesk_id = ticket_hash['id'] || ticket_hash[:id]
    ticket = ZendeskTicket.find_or_initialize_by(
      zendesk_id: zendesk_id,
      domain: domain
    )

    # Update all fields from the API response
    ticket_hash.each do |key, value|
      # Convert symbol keys to strings
      field_name = key.to_s
      # Skip id and domain as they're already set
      next if field_name == 'id' || field_name == 'domain'

      # Handle timestamp fields
      if field_name.end_with?('_at') && value.is_a?(String)
        begin
          ticket[field_name] = Time.parse(value)
        rescue ArgumentError
          ticket[field_name] = value
        end
      else
        ticket[field_name] = value
      end
    end

    ticket.save!
  rescue StandardError => e
    Rails.logger.error "Error saving ticket #{ticket_hash['id']}: #{e.message}"
    # Continue processing other tickets
  end
end
