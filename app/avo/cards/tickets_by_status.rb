module Avo
  module Cards
    class TicketsByStatus
      def query
        ZendeskTicket
          .where.not(status: nil)
          .group(:status)
          .count
      end
    end
  end
end
