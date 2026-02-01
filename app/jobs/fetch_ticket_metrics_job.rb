# frozen_string_literal: true

class FetchTicketMetricsJob < FetchTicketDetailJobBase
  queue_as :metrics
  queue_with_priority 10 # Higher priority than comments - process metrics after incremental jobs

  private

  def api_path(ticket_id)
    "/api/v2/tickets/#{ticket_id}/metrics.json"
  end

  def response_key
    "ticket_metric"
  end

  def resource_name
    "metrics"
  end

  def delay_env_var
    "METRICS_JOB_DELAY_SECONDS"
  end

  def log_received(ticket_id, data)
    keys = data.keys.join(", ")
    job_log(:info, "[#{job_name}] Received metrics data for ticket #{ticket_id}: #{keys}")
  end

  def persist_data(ticket, data)
    ticket.assign_metrics_data(data)

    extracted_metrics = []
    if ticket.first_reply_time_in_minutes
      extracted_metrics << "first_reply_time: #{ticket.first_reply_time_in_minutes}min"
    end
    if ticket.first_resolution_time_in_minutes
      extracted_metrics << "first_resolution_time: #{ticket.first_resolution_time_in_minutes}min"
    end
    if ticket.full_resolution_time_in_minutes
      extracted_metrics << "full_resolution_time: #{ticket.full_resolution_time_in_minutes}min"
    end
    extracted_metrics << "reopens: #{ticket.reopens}" if ticket.reopens
    extracted_metrics << "replies: #{ticket.replies}" if ticket.replies
    if extracted_metrics.any?
      job_log(:info,
        "[#{job_name}] Extracted metrics for ticket #{ticket.zendesk_id}: #{extracted_metrics.join(", ")}")
    end

    ticket.save!
  end
end
