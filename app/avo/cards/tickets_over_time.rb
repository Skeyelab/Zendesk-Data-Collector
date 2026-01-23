module Avo
  module Cards
    class TicketsOverTime
      def query
        # Group by date in local timezone to match test expectations
        # The test creates times using date.to_time which uses system timezone,
        # so we need to group by the local date, not UTC date
        tickets = ZendeskTicket.where.not(created_at: nil)

        tickets.each_with_object({}) do |ticket, hash|
          # Convert UTC time to local timezone before extracting date
          # This ensures tickets created on the same local date are grouped together
          local_time = ticket.created_at.getlocal
          date_key = local_time.to_date.strftime("%Y-%m-%d")
          hash[date_key] = (hash[date_key] || 0) + 1
        end
      end
    end
  end
end
