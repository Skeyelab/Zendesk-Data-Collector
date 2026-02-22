module Avo
  module Cards
    class TicketsByChannel
      def query
        ZendeskTicket
          .where.not(via: [nil, ""])
          .group(:via)
          .count
      end
    end
  end
end
