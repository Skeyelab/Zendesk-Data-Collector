class ApplicationJob < ActiveJob::Base
  around_perform do |job, block|
    Rails.logger.info "[#{job.class.name}] Starting"
    block.call
  ensure
    Rails.logger.info "[#{job.class.name}] Stopping"
  end

  # Log to both Rails.logger and stdout for visibility in job runners.
  def job_log(level, message)
    Rails.logger.public_send(level, message)
    puts message
  end

  # Helper for logging errors with class, message, and backtrace
  def job_log_error(error, context = "")
    prefix = context.present? ? "#{context}: " : ""
    job_log(:error, "[#{self.class.name}] #{prefix}#{error.message}")
    job_log(:error, "[#{self.class.name}] #{error.class}: #{error.message}")
    job_log(:error, "[#{self.class.name}] Backtrace:\n#{error.backtrace.join("\n")}")
  end
end
