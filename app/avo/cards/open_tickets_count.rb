module Avo
  module Cards
    class OpenTicketsCount
      def query
        ZendeskTicket.where(status: %w[new open pending]).count
      end
    end
  end
end
