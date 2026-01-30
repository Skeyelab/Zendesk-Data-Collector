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

  # Reset queued flag for desks that have been queued for too long (likely stuck)
  scope :stuck_queued, -> {
    where(queued: true, active: true)
      .where("updated_at < ?", 5.minutes.ago)
  }

  def self.reset_stuck_queued_flags!
    stuck_count = stuck_queued.count
    if stuck_count > 0
      stuck_queued.update_all(queued: false)
      Rails.logger.info "[Desk] Reset #{stuck_count} stuck queued flag(s)"
    end
    stuck_count
  end

  after_initialize :defaults, unless: :persisted?

  def defaults
    self.last_timestamp ||= 0
    self.last_timestamp_event ||= 0
    self.wait_till ||= 0
    self.wait_till_event ||= 0
    self.active ||= false
    self.queued ||= false
    self.fetch_comments = true if fetch_comments.nil?
    self.fetch_metrics = true if fetch_metrics.nil?
  end
end
