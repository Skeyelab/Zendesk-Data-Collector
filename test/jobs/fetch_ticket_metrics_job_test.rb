require "test_helper"
require "webmock/minitest"

class FetchTicketMetricsJobTest < ActiveJob::TestCase
  def setup
    @desk = Desk.create!(
      domain: "test.zendesk.com",
      user: "test@example.com",
      token: "test_token",
      last_timestamp: 1000,
      active: true,
      queued: false
    )

    @ticket = ZendeskTicket.create!(
      zendesk_id: 12_345,
      domain: "test.zendesk.com",
      subject: "Test Ticket",
      status: "open",
      raw_data: {
        "id" => 12_345,
        "subject" => "Test Ticket",
        "status" => "open"
      }
    )
  end

  def stub_metrics_api(ticket_id, metrics_data = {}, status: 200)
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/#{ticket_id}/metrics.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: status,
        body: {ticket_metric: metrics_data}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
  end

  test "waits when desk wait_till is in the future (wait_if_rate_limited)" do
    @desk.update_column(:wait_till, Time.now.to_i + 1)
    stub_metrics_api(12_345, {reopens: 0})
    FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    # In test we skip sleep (see ZendeskRateLimitHandler); we only assert the job runs the wait path and then completes
    @ticket.reload
    assert_not_nil @ticket.raw_data["metrics"], "Job should complete and store metrics after wait path"
  end

  test "does not wait for rate limit when desk wait_till is in the past" do
    @desk.update_columns(wait_till: 0)
    stub_metrics_api(12_345, {reopens: 0})
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    # Throttle (0.5s) + API; no multi-second wait from wait_till
    assert elapsed < 3, "Job should complete without long rate-limit wait, elapsed=#{elapsed}s"
  end

  test "throttle_using_rate_limit_headers runs when rate limit headers show low remaining" do
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/12345/metrics.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {ticket_metric: {reopens: 0}}.to_json,
        headers: {
          "Content-Type" => "application/json",
          "X-Rate-Limit" => "700",
          "X-Rate-Limit-Remaining" => "70",
          "ratelimit-reset" => "1"
        }
      )
    assert_nothing_raised do
      FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end
    @ticket.reload
    assert @ticket.raw_data["metrics"] || @ticket.reopens.present?, "Job should complete and update ticket"
  end

  test "should fetch and update ticket metrics" do
    metrics_data = {
      reply_time_in_minutes: {
        business: 737,
        calendar: 2391
      },
      first_resolution_time_in_minutes: {
        business: 500,
        calendar: 1800
      },
      full_resolution_time_in_minutes: {
        business: 600,
        calendar: 2000
      },
      agent_wait_time_in_minutes: {
        business: 100,
        calendar: 300
      },
      requester_wait_time_in_minutes: {
        business: 200,
        calendar: 500
      },
      on_hold_time_in_minutes: {
        business: 50,
        calendar: 150
      },
      assigned_at: "2011-05-05T10:38:52Z",
      solved_at: "2011-05-09T10:38:52Z",
      status_updated_at: "2011-05-04T10:38:52Z",
      latest_comment_added_at: "2011-05-09T10:38:52Z",
      requester_updated_at: "2011-05-07T10:38:52Z",
      assignee_updated_at: "2011-05-06T10:38:52Z",
      custom_status_updated_at: "2011-05-09T10:38:52Z",
      initially_assigned_at: "2011-05-03T10:38:52Z",
      created_at: "2009-07-20T22:55:29Z",
      updated_at: "2011-05-05T10:38:52Z",
      reopens: 2,
      replies: 5,
      assignee_stations: 1,
      group_stations: 3
    }

    stub_metrics_api(12_345, metrics_data)

    FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")

    @ticket.reload
    assert_not_nil @ticket.raw_data["metrics"]
    assert_equal 2391, @ticket.first_reply_time_in_minutes
    assert_equal 737, @ticket.first_reply_time_in_minutes_within_business_hours
    assert_equal 1800, @ticket.first_resolution_time_in_minutes
    assert_equal 500, @ticket.first_resolution_time_in_minutes_within_business_hours
    assert_equal 2000, @ticket.full_resolution_time_in_minutes
    assert_equal 600, @ticket.full_resolution_time_in_minutes_within_business_hours
    assert_equal 300, @ticket.agent_wait_time_in_minutes
    assert_equal 100, @ticket.agent_wait_time_in_minutes_within_business_hours
    assert_equal 500, @ticket.requester_wait_time_in_minutes
    assert_equal 200, @ticket.requester_wait_time_in_minutes_within_business_hours
    assert_equal 150, @ticket.on_hold_time_in_minutes
    assert_equal 50, @ticket.on_hold_time_in_minutes_within_business_hours
    assert_not_nil @ticket.assigned_at
    assert_not_nil @ticket.solved_at
    assert_not_nil @ticket.initially_assigned_at
    # These columns may not exist if migration was rolled back
    # Just verify the job doesn't crash
    # Schema has these as strings, so they'll be strings
    assert_equal "2", @ticket.reopens
    assert_equal "5", @ticket.replies
    assert_equal "1", @ticket.assignee_stations
    assert_equal "3", @ticket.group_stations
  end

  test "should extract nested time metrics correctly" do
    metrics_data = {
      reply_time_in_minutes: {
        business: 100,
        calendar: 500
      },
      first_resolution_time_in_minutes: {
        business: 200,
        calendar: 800
      }
    }

    stub_metrics_api(12_345, metrics_data)

    FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")

    @ticket.reload
    # Calendar value goes to main column
    assert_equal 500, @ticket.first_reply_time_in_minutes
    # Business value goes to _within_business_hours column
    assert_equal 100, @ticket.first_reply_time_in_minutes_within_business_hours
    assert_equal 800, @ticket.first_resolution_time_in_minutes
    assert_equal 200, @ticket.first_resolution_time_in_minutes_within_business_hours
  end

  test "should handle missing ticket gracefully" do
    # Should not raise an error, just log a warning
    assert_nothing_raised do
      FetchTicketMetricsJob.perform_now(99_999, @desk.id, "test.zendesk.com")
    end
  end

  test "should handle API errors gracefully" do
    stub_metrics_api(12_345, {}, status: 500)

    assert_nothing_raised do
      FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end

    @ticket.reload
    # Ticket should still exist, metrics should not be updated
    assert_not_nil @ticket
    assert_nil @ticket.raw_data["metrics"]
  end

  test "should handle rate limiting (429 error) with retry" do
    metrics_data = {
      reply_time_in_minutes: {
        business: 100,
        calendar: 500
      },
      reopens: 1,
      replies: 2
    }

    # First call returns 429, second succeeds
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/12345/metrics.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        {
          status: 429,
          headers: {
            "Retry-After" => "1"
          }
        },
        {
          status: 200,
          body: {ticket_metric: metrics_data}.to_json,
          headers: {"Content-Type" => "application/json"}
        }
      )

    assert_nothing_raised do
      FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end

    @desk.reload
    # wait_till should be set from the rate limit
    assert_not_nil @desk.wait_till
    assert @desk.wait_till > 0

    @ticket.reload
    # Metrics should be updated after retry
    assert_not_nil @ticket.raw_data["metrics"]
    assert_equal 500, @ticket.first_reply_time_in_minutes
    assert_equal "1", @ticket.reopens
    assert_equal "2", @ticket.replies
  end

  test "should handle empty metrics response" do
    stub_metrics_api(12_345, {})

    assert_nothing_raised do
      FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end

    @ticket.reload
    # Should not crash
    assert_not_nil @ticket
  end

  test "should preserve existing raw_data when updating metrics" do
    # Set some existing data in raw_data
    @ticket.update_columns(raw_data: {
      "id" => 12_345,
      "subject" => "Test Ticket",
      "status" => "open",
      "priority" => "high",
      "custom_field" => "value"
    })

    metrics_data = {
      reply_time_in_minutes: {
        business: 100,
        calendar: 500
      },
      reopens: 1
    }

    stub_metrics_api(12_345, metrics_data)

    FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")

    @ticket.reload
    # Should preserve existing fields
    assert_equal "Test Ticket", @ticket.raw_data["subject"]
    assert_equal "open", @ticket.raw_data["status"]
    assert_equal "high", @ticket.raw_data["priority"]
    assert_equal "value", @ticket.raw_data["custom_field"]
    # Should add metrics
    assert_not_nil @ticket.raw_data["metrics"]
  end

  test "should handle max retries on rate limit" do
    # Always return 429
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/12345/metrics.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 429,
        headers: {
          "Retry-After" => "1"
        }
      )

    assert_nothing_raised do
      FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end

    @ticket.reload
    # Metrics should not be updated after max retries
    assert_nil @ticket.raw_data["metrics"]
  end

  test "should handle network errors gracefully" do
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/12345/metrics.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_raise(StandardError.new("Network error"))

    assert_nothing_raised do
      FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end

    @ticket.reload
    # Ticket should still exist
    assert_not_nil @ticket
  end

  test "should store metrics in raw_data" do
    metrics_data = {
      reply_time_in_minutes: {
        business: 100,
        calendar: 500
      },
      reopens: 1,
      replies: 2,
      reply_time_in_seconds: {
        calendar: 30_000
      }
    }

    stub_metrics_api(12_345, metrics_data)

    FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")

    @ticket.reload
    # Full metrics should be stored in raw_data
    assert_not_nil @ticket.raw_data["metrics"]
    assert_equal 500, @ticket.raw_data["metrics"]["reply_time_in_minutes"]["calendar"]
    assert_equal 100, @ticket.raw_data["metrics"]["reply_time_in_minutes"]["business"]
    assert_equal 1, @ticket.raw_data["metrics"]["reopens"]
    assert_equal 2, @ticket.raw_data["metrics"]["replies"]
    # reply_time_in_seconds should be in raw_data but not extracted to columns
    assert_not_nil @ticket.raw_data["metrics"]["reply_time_in_seconds"]
  end

  test "should update count fields as strings" do
    metrics_data = {
      reopens: 5,
      replies: 10,
      assignee_stations: 2,
      group_stations: 4
    }

    stub_metrics_api(12_345, metrics_data)

    FetchTicketMetricsJob.perform_now(12_345, @desk.id, "test.zendesk.com")

    @ticket.reload
    # Count fields are stored as strings in the schema
    assert_equal "5", @ticket.reopens
    assert_equal "10", @ticket.replies
    assert_equal "2", @ticket.assignee_stations
    assert_equal "4", @ticket.group_stations
    assert_instance_of String, @ticket.reopens
    assert_instance_of String, @ticket.replies
    assert_instance_of String, @ticket.assignee_stations
    assert_instance_of String, @ticket.group_stations
  end
end
