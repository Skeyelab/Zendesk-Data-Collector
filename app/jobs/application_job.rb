class ApplicationJob < ActiveJob::Base
  around_perform do |job, block|
    Rails.logger.info "[#{job.class.name}] Starting"
    block.call
  ensure
    Rails.logger.info "[#{job.class.name}] Stopping"
  end
end
