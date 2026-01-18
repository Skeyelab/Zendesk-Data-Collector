class IncrementalTicketJob < ApplicationJob
  queue_as :default

  def perform(desk_id)
    desk = Desk.find(desk_id)
    client = ZendeskClientService.connect(desk)
    start_time = desk.last_timestamp

    # Verify MongoDB connection before starting
    unless verify_mongodb_connection
      Rails.logger.error "MongoDB connection check failed for desk #{desk_id}, aborting job"
      desk.queued = false
      desk.save
      return
    end

    tickets_saved = 0
    tickets_skipped = 0
    tickets_failed = 0

    begin
      tickets = client.tickets.incremental_export(start_time)
      total_tickets = tickets.count if tickets.respond_to?(:count)

      Rails.logger.info "Processing tickets for desk #{desk_id} (domain: #{desk.domain}), start_time: #{start_time}"

      tickets.each do |ticket_data|
        result = save_ticket_to_mongodb(ticket_data, desk.domain)
        if result[:success]
          tickets_saved += 1
        elsif result[:skipped]
          tickets_skipped += 1
        else
          tickets_failed += 1
        end
      end

      Rails.logger.info "Completed processing for desk #{desk_id}: #{tickets_saved} saved, #{tickets_skipped} skipped, #{tickets_failed} failed"

      # Update desk timestamp if we got new data
      if tickets.respond_to?(:included) && tickets.included
        if tickets.included['end_time']
          new_timestamp = tickets.included['end_time']
          if new_timestamp > 0 && new_timestamp > start_time
            desk.last_timestamp = new_timestamp
            desk.save
            Rails.logger.info "Updated last_timestamp for desk #{desk_id} to #{new_timestamp}"
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Error processing tickets for desk #{desk_id}: #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    ensure
      desk.queued = false
      desk.save
    end
  end

  private

  def verify_mongodb_connection
    begin
      Mongoid.default_client.database.command(ping: 1)
      true
    rescue Mongo::Error::ServerNotAvailable, Mongo::Error::NoServerAvailable => e
      Rails.logger.error "MongoDB server not available: #{e.class}: #{e.message}"
      false
    rescue Mongo::Error => e
      Rails.logger.error "MongoDB connection error: #{e.class}: #{e.message}"
      false
    rescue => e
      Rails.logger.error "Unexpected error checking MongoDB connection: #{e.class}: #{e.message}"
      false
    end
  end

  def save_ticket_to_mongodb(ticket_data, domain)
    # Convert ticket data to hash if it's not already
    ticket_hash = ticket_data.is_a?(Hash) ? ticket_data : ticket_data.to_h

    # Ensure domain is set
    ticket_hash['domain'] = domain

    # Find or initialize ticket
    zendesk_id = ticket_hash['id'] || ticket_hash[:id]

    if zendesk_id.nil?
      Rails.logger.warn "Skipping ticket with no ID: #{ticket_hash.inspect[0..200]}"
      return { success: false, skipped: true }
    end

    begin
      ticket = ZendeskTicket.find_or_initialize_by(
        zendesk_id: zendesk_id,
        domain: domain
      )

      was_new_record = ticket.new_record?

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

      if was_new_record
        Rails.logger.debug "Created ticket #{zendesk_id} for domain #{domain}"
      else
        Rails.logger.debug "Updated ticket #{zendesk_id} for domain #{domain}"
      end

      { success: true, skipped: false }
    rescue Mongo::Error::ServerNotAvailable, Mongo::Error::NoServerAvailable => e
      Rails.logger.error "MongoDB server not available when saving ticket #{zendesk_id}: #{e.class}: #{e.message}"
      { success: false, skipped: false, error: e }
    rescue Mongo::Error => e
      Rails.logger.error "MongoDB error saving ticket #{zendesk_id}: #{e.class}: #{e.message}"
      Rails.logger.error "Error details: #{e.inspect}"
      { success: false, skipped: false, error: e }
    rescue Mongoid::Errors::Validations => e
      Rails.logger.error "Validation error saving ticket #{zendesk_id}: #{e.message}"
      Rails.logger.error "Ticket data: #{ticket_hash.inspect[0..500]}"
      { success: false, skipped: false, error: e }
    rescue StandardError => e
      Rails.logger.error "Error saving ticket #{zendesk_id}: #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      { success: false, skipped: false, error: e }
    end
  end
end
