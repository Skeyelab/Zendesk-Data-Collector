# Respects Zendesk Incremental Exports limit (10/min, 30 with High Volume).
# See: https://developer.zendesk.com/api-reference/introduction/rate-limits/
class QueueIncrementalTicketsJob < ApplicationJob
  queue_as :default

  def perform
    # Reset stuck queued flags before checking for ready desks
    stuck_reset = Desk.reset_stuck_queued_flags!
    if stuck_reset > 0
      reset_msg = "[QueueIncrementalTicketsJob] Reset #{stuck_reset} stuck queued flag(s)"
      Rails.logger.info reset_msg
      puts reset_msg
    end

    IncrementalExportRequest.prune_old!

    if IncrementalExportRequest.at_cap?
      cap_msg = "[QueueIncrementalTicketsJob] Incremental export cap reached (last minute), skipping this run"
      Rails.logger.info cap_msg
      puts cap_msg
      return
    end

    checking_msg = "[QueueIncrementalTicketsJob] Checking for ready desks..."
    Rails.logger.info checking_msg
    puts checking_msg

    desks = Desk.readyToGo.order("last_timestamp desc")
    desk_count = desks.count

    if desk_count > 0
      found_msg = "[QueueIncrementalTicketsJob] Found #{desk_count} ready desk(s)"
      Rails.logger.info found_msg
      puts found_msg

      queued = 0
      desks.each do |desk|
        break if IncrementalExportRequest.at_cap?

        queue_msg = "[QueueIncrementalTicketsJob] Queuing job for desk: #{desk.domain} (ID: #{desk.id}, last_timestamp: #{desk.last_timestamp})"
        Rails.logger.info queue_msg
        puts queue_msg
        desk.queued = true
        desk.save
        IncrementalExportRequest.record_request!
        IncrementalTicketJob.perform_later(desk.id)
        queued += 1
      end

      queued_msg = "[QueueIncrementalTicketsJob] Queued #{queued} job(s)"
      Rails.logger.info queued_msg
      puts queued_msg
    else
      no_desks_msg = "[QueueIncrementalTicketsJob] No ready desks found"
      Rails.logger.info no_desks_msg
      puts no_desks_msg
    end
  end
end
