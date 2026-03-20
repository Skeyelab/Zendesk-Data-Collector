# frozen_string_literal: true

class FetchTicketCommentsJob < FetchTicketDetailJobBase
  queue_as :comments
  queue_with_priority 10 # Lower priority - process comments after incremental jobs

  private

  def api_path(ticket_id)
    "/api/v2/tickets/#{ticket_id}/comments.json"
  end

  def response_key
    "comments"
  end

  def resource_name
    "comments"
  end

  def delay_env_var
    "COMMENT_JOB_DELAY_SECONDS"
  end

  def empty_value
    []
  end

  def persist_when_empty?(data)
    data.is_a?(Array) && data.empty?
  end

  def log_received(ticket_id, data)
    job_log(:info, "[#{job_name}] Retrieved #{data.size} comment(s) for ticket #{ticket_id}")
  end

  def persist_data(ticket, data)
    rows = data.filter_map { |c| map_comment(ticket, c) }
    if rows.any?
      ZendeskTicketComment.upsert_all(rows, unique_by: [:zendesk_ticket_id, :zendesk_comment_id])
    end
    ticket.update_columns(raw_data: ticket.raw_data.except("comments"))
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
      created_at: comment["created_at"]
    }
  end
end
