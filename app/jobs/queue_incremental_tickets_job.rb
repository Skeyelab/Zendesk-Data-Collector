# Respects Zendesk Incremental Exports limit (10/min, 30 with High Volume).
# See: https://developer.zendesk.com/api-reference/introduction/rate-limits/
class QueueIncrementalTicketsJob < ApplicationJob
  queue_as :default

  def perform
    # Reset stuck queued flags before checking for ready desks
    stuck_reset = Desk.reset_stuck_queued_flags!
    if stuck_reset > 0
      job_log(:info, "[QueueIncrementalTicketsJob] Reset #{stuck_reset} stuck queued flag(s)")
    end

    IncrementalExportRequest.prune_old!

    if IncrementalExportRequest.at_cap?
      job_log(:info, "[QueueIncrementalTicketsJob] Incremental export cap reached (last minute), skipping this run")
      return
    end

    job_log(:info, "[QueueIncrementalTicketsJob] Checking for ready desks...")

    desks = Desk.readyToGo.order("last_timestamp desc")
    desk_count = desks.count

    if desk_count > 0
      job_log(:info, "[QueueIncrementalTicketsJob] Found #{desk_count} ready desk(s)")

      queued = 0
      desks.each do |desk|
        break if IncrementalExportRequest.at_cap?

        job_log(:info, "[QueueIncrementalTicketsJob] Queuing job for desk: #{desk.domain} (ID: #{desk.id}, last_timestamp: #{desk.last_timestamp})")
        desk.queued = true
        desk.save
        IncrementalExportRequest.record_request!
        IncrementalTicketJob.perform_later(desk.id)
        queued += 1
      end

      job_log(:info, "[QueueIncrementalTicketsJob] Queued #{queued} job(s)")
    else
      job_log(:info, "[QueueIncrementalTicketsJob] No ready desks found")
    end
  end
end
