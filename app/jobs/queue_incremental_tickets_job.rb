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

    checking_msg = "[QueueIncrementalTicketsJob] Checking for ready desks..."
    Rails.logger.info checking_msg
    puts checking_msg

    desks = Desk.readyToGo.order("last_timestamp desc")
    desk_count = desks.count

    if desk_count > 0
      found_msg = "[QueueIncrementalTicketsJob] Found #{desk_count} ready desk(s)"
      Rails.logger.info found_msg
      puts found_msg

      desks.each do |desk|
        queue_msg = "[QueueIncrementalTicketsJob] Queuing job for desk: #{desk.domain} (ID: #{desk.id}, last_timestamp: #{desk.last_timestamp})"
        Rails.logger.info queue_msg
        puts queue_msg
        desk.queued = true
        desk.save
        IncrementalTicketJob.perform_later(desk.id)
      end

      queued_msg = "[QueueIncrementalTicketsJob] Queued #{desk_count} job(s)"
      Rails.logger.info queued_msg
      puts queued_msg
    else
      no_desks_msg = "[QueueIncrementalTicketsJob] No ready desks found"
      Rails.logger.info no_desks_msg
      puts no_desks_msg
    end
  end
end
