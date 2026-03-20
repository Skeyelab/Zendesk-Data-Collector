# frozen_string_literal: true

# Nested creates (e.g. comments on a ticket) use Avo::AssociationsController, not ResourcesController.

Rails.application.config.to_prepare do
  next unless defined?(Avo::AssociationsController)

  Avo::AssociationsController.class_eval do
    prepend_before_action :forbid_view_only_association_writes, only: %i[new create destroy]

    private

    def forbid_view_only_association_writes
      names = %w[zendesk_ticket_comments zendesk_tickets]
      return unless names.include?(params[:related_name].to_s)

      head :forbidden
    end
  end
end
