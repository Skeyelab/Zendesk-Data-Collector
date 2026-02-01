# frozen_string_literal: true

class FetchTicketCommentsJob < FetchTicketDetailJobBase
  queue_as :comments
  queue_with_priority 10 # Lower priority - process comments after incremental jobs

  private

  def api_path(ticket_id)
    "/api/v2/tickets/#{ticket_id}/comments.json"
  end

  def response_key
    'comments'
  end

  def resource_name
    'comments'
  end

  def delay_env_var
    'COMMENT_JOB_DELAY_SECONDS'
  end

  def empty_value
    []
  end

  def log_received(ticket_id, data)
    job_log(:info, "[#{job_name}] Retrieved #{data.size} comment(s) for ticket #{ticket_id}")
  end

  def persist_data(ticket, data)
    updated_raw_data = ticket.raw_data.merge('comments' => data)
    ticket.update_columns(raw_data: updated_raw_data)
  end
end
