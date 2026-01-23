module Avo
  module Cards
    class TicketsByDomain
      def query
        ZendeskTicket
          .where.not(domain: nil)
          .group(:domain)
          .count
      end
    end
  end
end
