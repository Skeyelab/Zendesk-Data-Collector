# frozen_string_literal: true

module Avo
  # Stock Avo (without avo-pro) uses a permissive AuthorizationService. This subclass
  # hides create/edit/destroy in the UI for synced Zendesk mirror models (tickets, comments).
  class ViewOnlyResourceAuthorization < Avo::Services::AuthorizationService
    DENIED = %i[new create edit update destroy act_on].freeze

    def authorize_action(*args, **kwargs)
      action = args.first

      if action.is_a?(Avo::ViewInquirer)
        return false if action.form?
        return true
      end

      return false if action.is_a?(Symbol) && DENIED.include?(action)
      if action.is_a?(String)
        base = action.downcase.delete_suffix("?")
        return false if DENIED.map(&:to_s).include?(base)
      end

      true
    end
  end
end
