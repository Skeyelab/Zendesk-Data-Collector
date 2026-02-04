class ZendeskTicketUpsertService
  def self.call(ticket_hash, domain)
    ticket_hash = ticket_hash.is_a?(Hash) ? ticket_hash : ticket_hash.to_h
    ticket_hash = ticket_hash.deep_stringify_keys
    ticket_hash["domain"] = domain

    zendesk_id = ticket_hash["id"] || ticket_hash["zendesk_id"]
    is_new = !ZendeskTicket.exists?(zendesk_id: zendesk_id, domain: domain)

    ticket = ZendeskTicket.find_or_initialize_by(zendesk_id: zendesk_id, domain: domain)
    ticket.assign_ticket_data(ticket_hash)
    ticket.save!

    is_new ? :created : :updated
  end
end
