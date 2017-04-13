class Desk < ApplicationRecord
  attr_encrypted :token, key: ENV["ENC_KEY"]

  after_initialize :defaults, unless: :persisted?
  after_create do
    createTableIfNeeded(domain)
  end

  def defaults
    self.last_timestamp||=0
    self.last_timestamp_event||=0
    self.wait_till||=0
    self.wait_till_event||=0
    self.active||=false
  end
end
