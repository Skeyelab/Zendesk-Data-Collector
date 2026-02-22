module Avo
  module Cards
    class SatisfactionScores
      def query
        ZendeskTicket
          .where.not(satisfaction_score: [nil, ""])
          .where.not(satisfaction_score: "unoffered")
          .group(:satisfaction_score)
          .count
      end
    end
  end
end
