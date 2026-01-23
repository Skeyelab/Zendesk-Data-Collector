module Avo
  module Cards
    class TicketsByPriority
      def query
        ZendeskTicket
          .where.not(priority: nil)
          .group(:priority)
          .count
      end
    end
  end
end
