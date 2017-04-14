class QueueIncrementalTicketsWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'data_collector_default'

  def perform()
    # Do something
    #qry = "select id from desks where last_timestamp <= #{Time.now.to_i-300} and wait_till < #{Time.now.to_i} and active = true order by last_timestamp desc;"
    #desks = GitHub::SQL.results qry
    desks = Desk.where("last_timestamp <= #{Time.now.to_i-300} and wait_till < #{Time.now.to_i} and active = true").order("last_timestamp desc")

    if desks.count > 0
      desks.each do |desk|

        puts "starting #{desk.domain}"
        IncrementalTicketWorker.perform_async(desk.id)
      end
    end
  end
end
