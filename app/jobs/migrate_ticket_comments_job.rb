# frozen_string_literal: true

# One-time backfill job: extracts comments from raw_data JSONB into the
# zendesk_ticket_comments table, then strips the key from raw_data.
#
# Trigger from Rails console:
#   MigrateTicketCommentsJob.perform_later
#
# Or with options:
#   MigrateTicketCommentsJob.perform_later(batch_size: 100)
class MigrateTicketCommentsJob < ApplicationJob
  queue_as :default
  queue_with_priority 50 # Low priority - this is background maintenance

  BATCH_SIZE = 200

  def perform(batch_size: BATCH_SIZE, last_id: 0, retry_ids: [])
    if retry_ids.present?
      retry_failed_tickets(retry_ids)
      return
    end

    batch = ZendeskTicket
      .where("id > ? AND jsonb_exists(raw_data, 'comments')", last_id)
      .order(:id)
      .limit(batch_size)

    return if batch.empty?

    failed_ids = []
    batch.each do |ticket|
      failed_ids << ticket.id unless migrate_ticket(ticket)
    end

    if failed_ids.any?
      Rails.logger.warn("[MigrateTicketCommentsJob] Re-enqueueing #{failed_ids.size} failed ticket(s) for retry: #{failed_ids.inspect}")
      self.class.perform_later(retry_ids: failed_ids)
    end

    remaining = ZendeskTicket.where("id > ? AND jsonb_exists(raw_data, 'comments')", batch.last.id).exists?
    if remaining
      self.class.perform_later(batch_size: batch_size, last_id: batch.last.id)
    else
      Rails.logger.info("[MigrateTicketCommentsJob] Backfill complete.")
    end
  end

  private

  def retry_failed_tickets(ids)
    ZendeskTicket.where(id: ids).find_each do |ticket|
      unless migrate_ticket(ticket)
        Rails.logger.error("[MigrateTicketCommentsJob] Retry also failed for ticket #{ticket.id}; giving up on this ticket.")
      end
    end
  end

  def migrate_ticket(ticket)
    comments = ticket.raw_data["comments"]
    if comments.present?
      rows = comments.filter_map { |c| map_comment(ticket, c) }
      ZendeskTicketComment.upsert_all(rows, unique_by: [:zendesk_ticket_id, :zendesk_comment_id]) if rows.any?
    end

    ticket.update_columns(raw_data: ticket.raw_data.except("comments"))
    true
  rescue => e
    Rails.logger.error("[MigrateTicketCommentsJob] Failed to migrate ticket #{ticket.id}: #{e.message}")
    false
  end

  def map_comment(ticket, comment)
    return nil if comment["id"].blank?

    {
      zendesk_ticket_id: ticket.id,
      zendesk_comment_id: comment["id"],
      author_id: comment["author_id"],
      body: comment["body"],
      plain_body: comment["plain_body"],
      public: comment.fetch("public", true),
      via: comment["via"],
      created_at: comment["created_at"] || ticket.created_at
    }
  end
end
