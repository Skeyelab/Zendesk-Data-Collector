module Avo
  class ZendeskTicketResourcesController < ResourcesController
    prepend_before_action :reject_ticket_writes!, except: %i[index show preview]

    private

    def reject_ticket_writes!
      head :forbidden
    end
  end
end
