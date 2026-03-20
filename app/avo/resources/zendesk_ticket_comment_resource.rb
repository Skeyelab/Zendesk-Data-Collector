# frozen_string_literal: true

class Avo::Resources::ZendeskTicketCommentResource < Avo::BaseResource
  self.model_class = ZendeskTicketComment
  self.title = :plain_body
  self.includes = []
  self.default_sort_column = :zendesk_comment_id
  self.default_sort_direction = :asc

  class << self
    def authorization
      ::Avo::ViewOnlyResourceAuthorization.new(Avo::Current.user, model_class, policy_class: authorization_policy)
    end
  end

  def authorization(user: nil)
    current_user = user || Avo::Current.user
    ::Avo::ViewOnlyResourceAuthorization.new(current_user, record || model_class, policy_class: self.class.authorization_policy)
  end

  def fields
    field :id, as: :id
    field :zendesk_comment_id, as: :number, readonly: true, sortable: true
    field :zendesk_ticket_id, as: :number, readonly: true, sortable: true
    field :author_id, as: :number, readonly: true
    field :public, as: :boolean, readonly: true, sortable: true

    field :plain_body, as: :text, readonly: true
    field :body, as: :text, readonly: true

    field :created_at, as: :date_time, readonly: true, sortable: true
    field :via, as: :code, readonly: true, language: :json,
      format_using: -> { value.is_a?(Hash) ? JSON.pretty_generate(value) : value.to_s }
  end
end
