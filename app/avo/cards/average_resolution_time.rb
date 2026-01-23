module Avo
  module Cards
    class AverageResolutionTime
      def query
        avg = ZendeskTicket
          .where.not(full_resolution_time_in_minutes: nil)
          .average(:full_resolution_time_in_minutes)

        return 0 if avg.nil?

        avg.floor.to_i
      end
    end
  end
end
