module Avo
  module Cards
    class ActiveDesksCount
      def query
        Desk.where(active: true, queued: false).count
      end
    end
  end
end
