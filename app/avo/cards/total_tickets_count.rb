module Avo
  module Cards
    class TotalTicketsCount
      def query
        ZendeskTicket.count
      end
    end
  end
end
