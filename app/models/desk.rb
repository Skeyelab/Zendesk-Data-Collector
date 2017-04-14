class Desk < ApplicationRecord
  attr_encrypted :token, key: ENV["SECRET_KEY_BASE"]

  scope :readyToGo, -> { where("last_timestamp <= #{Time.now.to_i-300} and wait_till < #{Time.now.to_i} and active = true and queued = false") }

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
    self.queued||=false
  end
end
