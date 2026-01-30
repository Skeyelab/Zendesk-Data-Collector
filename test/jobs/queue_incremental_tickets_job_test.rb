require "test_helper"

class QueueIncrementalTicketsJobTest < ActiveJob::TestCase
  test "enqueues incremental jobs for ready desks" do
    ready_desk = Desk.create!(
      domain: "ready.zendesk.com",
      user: "ready@example.com",
      token: "token",
      last_timestamp: Time.now.to_i - 600,
      wait_till: Time.now.to_i - 100,
      active: true,
      queued: false
    )

    not_ready_desk = Desk.create!(
      domain: "queued.zendesk.com",
      user: "queued@example.com",
      token: "token",
      last_timestamp: Time.now.to_i - 600,
      wait_till: Time.now.to_i - 100,
      active: true,
      queued: true
    )

    assert_enqueued_with(job: IncrementalTicketJob, args: [ready_desk.id]) do
      assert_enqueued_jobs 1, only: IncrementalTicketJob do
        QueueIncrementalTicketsJob.perform_now
      end
    end

    ready_desk.reload
    not_ready_desk.reload
    assert_equal true, ready_desk.queued
    assert_equal true, not_ready_desk.queued
  end

  test "does not queue incremental jobs when at cap (10 per minute)" do
    10.times { IncrementalExportRequest.create!(requested_at: Time.current) }
    desk = Desk.create!(
      domain: "cap.zendesk.com",
      user: "cap@example.com",
      token: "token",
      last_timestamp: Time.now.to_i - 600,
      wait_till: Time.now.to_i - 100,
      active: true,
      queued: false
    )

    assert_enqueued_jobs 0, only: IncrementalTicketJob do
      QueueIncrementalTicketsJob.perform_now
    end

    desk.reload
    assert_equal false, desk.queued
  end

  # Design: each desk has its own rate limit (wait_till). When one desk hits 429 we throttle only that desk;
  # readyToGo excludes desks with wait_till in future, so work continues on other desks.
  test "with multiple desks, only desks not rate-limited are queued (work continues on others)" do
    # Desk A: rate-limited (hit 429), wait_till in future
    desk_a = Desk.create!(
      domain: "rate-limited.zendesk.com",
      user: "a@example.com",
      token: "token",
      last_timestamp: Time.now.to_i - 600,
      wait_till: Time.now.to_i + 60, # rate limited
      active: true,
      queued: false
    )
    # Desk B: ready, not rate-limited
    desk_b = Desk.create!(
      domain: "ready-other.zendesk.com",
      user: "b@example.com",
      token: "token",
      last_timestamp: Time.now.to_i - 600,
      wait_till: Time.now.to_i - 100,
      active: true,
      queued: false
    )

    assert_enqueued_jobs 1, only: IncrementalTicketJob do
      assert_enqueued_with(job: IncrementalTicketJob, args: [desk_b.id]) do
        QueueIncrementalTicketsJob.perform_now
      end
    end

    desk_a.reload
    desk_b.reload
    assert_equal false, desk_a.queued, "Rate-limited desk A should not be queued"
    assert_equal true, desk_b.queued, "Ready desk B should be queued"
  end

  # When there is only one desk and it is rate-limited, we throttle (no jobs enqueued).
  test "with one desk rate-limited, no jobs enqueued (throttle single desk)" do
    desk = Desk.create!(
      domain: "only-desk.zendesk.com",
      user: "only@example.com",
      token: "token",
      last_timestamp: Time.now.to_i - 600,
      wait_till: Time.now.to_i + 30, # only desk is rate-limited
      active: true,
      queued: false
    )

    assert_enqueued_jobs 0, only: IncrementalTicketJob do
      QueueIncrementalTicketsJob.perform_now
    end

    desk.reload
    assert_equal false, desk.queued
  end

  test "should not enqueue jobs when no desks are ready" do
    # Create desks that are not ready
    Desk.create!(
      domain: "inactive.zendesk.com",
      user: "inactive@example.com",
      token: "token",
      active: false,
      queued: false
    )

    Desk.create!(
      domain: "too-recent.zendesk.com",
      user: "recent@example.com",
      token: "token",
      last_timestamp: Time.now.to_i - 100, # Too recent
      wait_till: Time.now.to_i - 100,
      active: true,
      queued: false
    )

    assert_enqueued_jobs 0, only: IncrementalTicketJob do
      QueueIncrementalTicketsJob.perform_now
    end
  end
end
