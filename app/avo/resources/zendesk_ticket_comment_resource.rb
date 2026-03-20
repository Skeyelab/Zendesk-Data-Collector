# frozen_string_literal: true

class Avo::Resources::ZendeskTicketCommentResource < Avo::BaseResource
  self.model_class = ZendeskTicketComment
  self.title = :plain_body
  self.includes = []
  self.default_sort_column = :created_at
  self.default_sort_direction = :asc

  def fields
    field :id, as: :id
    field :zendesk_comment_id, as: :number, sortable: true
    field :zendesk_ticket_id, as: :number, readonly: true, sortable: true
    field :author_id, as: :number
    field :public, as: :boolean, sortable: true

    field :plain_body, as: :text
    field :body, as: :text, readonly: true

    field :created_at, as: :date_time, readonly: true, sortable: true
    field :via, as: :code, readonly: true, language: :json,
      format_using: -> { value.is_a?(Hash) ? JSON.pretty_generate(value) : value.to_s }
  end
end
