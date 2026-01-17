class QueueIncrementalTicketsJob < ApplicationJob
  queue_as :default

  def perform
    desks = Desk.readyToGo.order("last_timestamp desc")
    if desks.count > 0
      desks.each do |desk|
        desk.queued = true
        desk.save
        Rails.logger.info "Starting ticket collection for #{desk.domain}"
        IncrementalTicketJob.perform_later(desk.id)
      end
    end
  end
end
