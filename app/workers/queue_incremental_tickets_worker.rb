class QueueIncrementalTicketsWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'data_collector_default'

  def perform()
    desks = Desk.readyToGo.order("last_timestamp desc")
    if desks.count > 0
      desks.each do |desk|
        desk.queued = true
        desk.save
        puts "starting #{desk.domain}"
        IncrementalTicketWorker.perform_async(desk.id)
      end
    end
  end
end
