# Tracks incremental export API requests to enforce Zendesk limit (10/min, 30 with High Volume).
# See: https://developer.zendesk.com/api-reference/introduction/rate-limits/
class IncrementalExportRequest < ApplicationRecord
  def self.count_in_last_minute
    where("requested_at > ?", 1.minute.ago).count
  end

  def self.at_cap?(max_per_minute: nil)
    max = max_per_minute || ENV.fetch("ZENDESK_INCREMENTAL_EXPORT_MAX_PER_MINUTE", "10").to_i
    count_in_last_minute >= max
  end

  def self.record_request!
    create!(requested_at: Time.current)
  end

  def self.prune_old!
    where("requested_at < ?", 2.minutes.ago).delete_all
  end
end
