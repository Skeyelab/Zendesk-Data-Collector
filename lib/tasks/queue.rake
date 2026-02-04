namespace :queue do
  desc "Show stuck jobs in SolidQueue"
  task stuck: :environment do
    puts "=== SolidQueue Job Status ==="
    puts

    # Check for active workers
    active_workers = SolidQueue::Process.where("last_heartbeat_at > ?", 1.minute.ago).count
    puts "Active Workers: #{active_workers}"
    puts "  ⚠️  WARNING: No active workers detected! Jobs won't be processed." if active_workers == 0
    puts

    # Failed jobs
    failed_count = SolidQueue::FailedExecution.count
    puts "Failed Jobs: #{failed_count}"
    if failed_count > 0
      SolidQueue::FailedExecution.includes(:job).limit(10).each do |failed|
        job = failed.job
        puts "  - #{job.class_name} (ID: #{job.id}, Created: #{job.created_at})"
        puts "    Error: #{failed.error&.split("\n")&.first}"
      end
      puts "  ... and #{failed_count - 10} more" if failed_count > 10
    end
    puts

    # Claimed jobs that are old (likely stuck)
    old_claimed = SolidQueue::ClaimedExecution
      .joins(:job)
      .where("solid_queue_claimed_executions.created_at < ?", 10.minutes.ago)
      .includes(:job)

    claimed_count = old_claimed.count
    puts "Old Claimed Jobs (likely stuck): #{claimed_count}"
    if claimed_count > 0
      old_claimed.limit(10).each do |claimed|
        job = claimed.job
        age = Time.current - claimed.created_at
        puts "  - #{job.class_name} (ID: #{job.id}, Age: #{age.to_i}s, Created: #{job.created_at})"
        puts "    Queue: #{job.queue_name}, Priority: #{job.priority}"
      end
      puts "  ... and #{claimed_count - 10} more" if claimed_count > 10
    end
    puts

    # Blocked jobs
    blocked_count = SolidQueue::BlockedExecution.count
    puts "Blocked Jobs: #{blocked_count}"
    if blocked_count > 0
      SolidQueue::BlockedExecution.includes(:job).limit(10).each do |blocked|
        job = blocked.job
        puts "  - #{job.class_name} (ID: #{job.id}, Expires: #{blocked.expires_at})"
        puts "    Concurrency Key: #{blocked.concurrency_key}"
      end
      puts "  ... and #{blocked_count - 10} more" if blocked_count > 10
    end
    puts

    # Scheduled jobs that are past due
    overdue_scheduled = SolidQueue::ScheduledExecution
      .joins(:job)
      .where("solid_queue_scheduled_executions.scheduled_at < ?", 5.minutes.ago)
      .where("solid_queue_jobs.finished_at IS NULL")
      .includes(:job)

    overdue_count = overdue_scheduled.count
    puts "Overdue Scheduled Jobs: #{overdue_count}"
    if overdue_count > 0
      overdue_scheduled.limit(10).each do |scheduled|
        job = scheduled.job
        overdue = Time.current - scheduled.scheduled_at
        puts "  - #{job.class_name} (ID: #{job.id}, Overdue: #{overdue.to_i}s, Scheduled: #{scheduled.scheduled_at})"
      end
      puts "  ... and #{overdue_count - 10} more" if overdue_count > 10
    end
    puts

    # Ready jobs
    ready_count = SolidQueue::ReadyExecution.count
    puts "Ready Jobs: #{ready_count}"
    if ready_count > 0
      oldest_ready = SolidQueue::ReadyExecution.joins(:job).order("solid_queue_jobs.created_at ASC").first
      if oldest_ready
        age = Time.current - oldest_ready.job.created_at
        puts "  Oldest ready job: #{age.to_i / 60} minutes old (created: #{oldest_ready.job.created_at})"
      end
    end
    puts

    # Jobs by queue
    puts "Jobs by Queue:"
    SolidQueue::Job
      .where(finished_at: nil)
      .group(:queue_name)
      .count
      .each do |queue, count|
        puts "  #{queue}: #{count}"
    end
    puts

    # Jobs by class
    puts "Jobs by Class (unfinished):"
    SolidQueue::Job
      .where(finished_at: nil)
      .group(:class_name)
      .count
      .sort_by { |_k, v| -v }
      .first(10)
      .each do |klass, count|
        puts "  #{klass}: #{count}"
    end
    puts

    total_stuck = failed_count + claimed_count + overdue_count
    if total_stuck > 0
      puts "⚠️  Total potentially stuck jobs: #{total_stuck}"
      puts "   Run 'rake queue:cleanup_stuck' to clean them up"
    else
      puts "✓ No stuck jobs found"
    end
  end

  desc "Clean up stuck jobs (old claimed, overdue scheduled, expired blocked)"
  task cleanup_stuck: :environment do
    puts "=== Cleaning Up Stuck Jobs ==="
    puts

    cleaned = 0

    # Release old claimed executions (jobs that have been claimed for > 10 minutes)
    old_claimed = SolidQueue::ClaimedExecution
      .where("created_at < ?", 10.minutes.ago)

    old_claimed_count = old_claimed.count
    if old_claimed_count > 0
      puts "Releasing #{old_claimed_count} old claimed executions..."
      old_claimed.delete_all
      cleaned += old_claimed_count
    end

    # Release expired blocked executions
    expired_blocked = SolidQueue::BlockedExecution
      .where("expires_at < ?", Time.current)

    expired_count = expired_blocked.count
    if expired_count > 0
      puts "Releasing #{expired_count} expired blocked executions..."
      expired_blocked.delete_all
      cleaned += expired_count
    end

    # Clean up old finished jobs (older than 7 days)
    old_finished = SolidQueue::Job
      .where("finished_at < ?", 7.days.ago)

    old_finished_count = old_finished.count
    if old_finished_count > 0
      puts "Cleaning up #{old_finished_count} old finished jobs..."
      old_finished.delete_all
      cleaned += old_finished_count
    end

    if cleaned > 0
      puts
      puts "✓ Cleaned up #{cleaned} stuck/old jobs"
    else
      puts "✓ No stuck jobs to clean up"
    end
  end

  desc "Show failed jobs with details"
  task failed: :environment do
    failed_count = SolidQueue::FailedExecution.count
    puts "=== Failed Jobs (#{failed_count}) ==="
    puts

    if failed_count > 0
      SolidQueue::FailedExecution.includes(:job).order(created_at: :desc).limit(20).each do |failed|
        job = failed.job
        puts "Job ID: #{job.id}"
        puts "Class: #{job.class_name}"
        puts "Queue: #{job.queue_name}"
        puts "Created: #{job.created_at}"
        puts "Failed: #{failed.created_at}"
        puts "Error:"
        puts failed.error
        puts "-" * 80
        puts
      end
    else
      puts "No failed jobs"
    end
  end

  desc "Show queue statistics"
  task stats: :environment do
    puts "=== Queue Statistics ==="
    puts

    # Total jobs
    total = SolidQueue::Job.count
    finished = SolidQueue::Job.where.not(finished_at: nil).count
    unfinished = SolidQueue::Job.where(finished_at: nil).count

    puts "Total Jobs: #{total}"
    puts "  Finished: #{finished}"
    puts "  Unfinished: #{unfinished}"
    puts

    # By status
    ready = SolidQueue::ReadyExecution.count
    scheduled = SolidQueue::ScheduledExecution.count
    claimed = SolidQueue::ClaimedExecution.count
    blocked = SolidQueue::BlockedExecution.count
    failed = SolidQueue::FailedExecution.count

    puts "Job Status:"
    puts "  Ready: #{ready}"
    puts "  Scheduled: #{scheduled}"
    puts "  Claimed: #{claimed}"
    puts "  Blocked: #{blocked}"
    puts "  Failed: #{failed}"
    puts

    # By queue
    puts "Jobs by Queue (unfinished):"
    SolidQueue::Job
      .where(finished_at: nil)
      .group(:queue_name)
      .count
      .sort_by { |_k, v| -v }
      .each do |queue, count|
        puts "  #{queue}: #{count}"
    end
    puts

    # By class
    puts "Jobs by Class (unfinished, top 10):"
    SolidQueue::Job
      .where(finished_at: nil)
      .group(:class_name)
      .count
      .sort_by { |_k, v| -v }
      .first(10)
      .each do |klass, count|
        puts "  #{klass}: #{count}"
    end
  end
end
