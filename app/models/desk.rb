class Desk < ApplicationRecord
  encrypts :token

  validates :domain, presence: true, uniqueness: true
  validates :user, presence: true
  validates :token, presence: true

  scope :readyToGo, -> {
    current_time = Time.now.to_i
    where("last_timestamp <= ? AND wait_till < ? AND active = ? AND queued = ?",
          current_time - 300, current_time, true, false)
  }

  after_initialize :defaults, unless: :persisted?

  def defaults
    self.last_timestamp ||= 0
    self.last_timestamp_event ||= 0
    self.wait_till ||= 0
    self.wait_till_event ||= 0
    self.active ||= false
    self.queued ||= false
  end
end
