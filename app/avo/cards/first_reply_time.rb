module Avo
  module Cards
    class FirstReplyTime
      def query
        avg = ZendeskTicket
          .where.not(first_reply_time_in_minutes: nil)
          .average(:first_reply_time_in_minutes)

        return 0 if avg.nil?

        avg.floor
      end
    end
  end
end
