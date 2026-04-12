# frozen_string_literal: true

# One-time backfill job: populates real_zendesk_id on existing
# zendesk_ticket_comments rows from the parent zendesk_tickets table.
#
# Trigger from Rails console:
#   BackfillRealZendeskIdJob.perform_later
#
# Or with a custom batch size:
#   BackfillRealZendeskIdJob.perform_later(batch_size: 1000)
class BackfillRealZendeskIdJob < ApplicationJob
  queue_as :default
  queue_with_priority 50 # Low priority - background maintenance

  BATCH_SIZE = 500

  def perform(batch_size: BATCH_SIZE, last_id: 0)
    ids = ZendeskTicketComment
      .where(real_zendesk_id: nil)
      .where("zendesk_ticket_comments.id > ?", last_id)
      .order(:id)
      .limit(batch_size)
      .pluck(:id)

    if ids.empty?
      job_log(:info, "[BackfillRealZendeskIdJob] Backfill complete.")
      return
    end

    updated = ZendeskTicketComment
      .where(id: ids)
      .joins("INNER JOIN zendesk_tickets ON zendesk_tickets.id = zendesk_ticket_comments.zendesk_ticket_id")
      .update_all("real_zendesk_id = zendesk_tickets.zendesk_id")

    job_log(:info, "[BackfillRealZendeskIdJob] Updated #{updated} row(s) (last id: #{ids.last})")

    self.class.perform_later(batch_size: batch_size, last_id: ids.last)
  end
end
