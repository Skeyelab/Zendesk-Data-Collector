module Avo
  module Cards
    class TicketsByAssignee
      def query
        ZendeskTicket
          .where.not(assignee_name: [nil, ""])
          .group(:assignee_name)
          .count
          .sort_by { |_name, count| -count }
          .first(10)
          .to_h
      end
    end
  end
end
