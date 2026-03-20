# frozen_string_literal: true

class ZendeskTicketComment < ApplicationRecord
  self.record_timestamps = false

  belongs_to :zendesk_ticket

  validates :zendesk_comment_id, presence: true
  validates :zendesk_ticket_id, presence: true
end
