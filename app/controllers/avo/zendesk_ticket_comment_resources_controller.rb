module Avo
  class ZendeskTicketCommentResourcesController < ResourcesController
    prepend_before_action :reject_ticket_comment_writes!, except: %i[index show preview]

    private

    def reject_ticket_comment_writes!
      head :forbidden
    end
  end
end
