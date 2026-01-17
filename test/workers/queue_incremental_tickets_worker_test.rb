require 'test_helper'

class QueueIncrementalTicketsWorkerTest < ActiveJob::TestCase
  test "enqueues incremental jobs for ready desks" do
    ready_desk = Desk.create!(
      domain: 'ready.zendesk.com',
      user: 'ready@example.com',
      token: 'token',
      last_timestamp: Time.now.to_i - 600,
      wait_till: Time.now.to_i - 100,
      active: true,
      queued: false
    )

    not_ready_desk = Desk.create!(
      domain: 'queued.zendesk.com',
      user: 'queued@example.com',
      token: 'token',
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

  test "should not enqueue jobs when no desks are ready" do
    # Create desks that are not ready
    Desk.create!(
      domain: 'inactive.zendesk.com',
      user: 'inactive@example.com',
      token: 'token',
      active: false,
      queued: false
    )

    Desk.create!(
      domain: 'too-recent.zendesk.com',
      user: 'recent@example.com',
      token: 'token',
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
