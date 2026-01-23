require "test_helper"
require "webmock/minitest"

class FetchTicketCommentsJobTest < ActiveJob::TestCase
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
      zendesk_id: 12345,
      domain: "test.zendesk.com",
      subject: "Test Ticket",
      status: "open",
      raw_data: {
        "id" => 12345,
        "subject" => "Test Ticket",
        "status" => "open"
      }
    )
  end

  def stub_comments_api(ticket_id, comments_data = [], status: 200)
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/#{ticket_id}/comments.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: status,
        body: {comments: comments_data}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
  end

  test "should fetch and update ticket comments" do
    comments_data = [
      {
        id: 1,
        type: "Comment",
        body: "This is the first comment",
        html_body: "<p>This is the first comment</p>",
        plain_body: "This is the first comment",
        public: true,
        author_id: 12345,
        created_at: "2024-01-01T10:00:00Z"
      },
      {
        id: 2,
        type: "Comment",
        body: "This is the second comment",
        html_body: "<p>This is the second comment</p>",
        plain_body: "This is the second comment",
        public: false,
        author_id: 67890,
        created_at: "2024-01-02T11:00:00Z"
      }
    ]

    stub_comments_api(12345, comments_data)

    FetchTicketCommentsJob.perform_now(12345, @desk.id, "test.zendesk.com")

    @ticket.reload
    assert_not_nil @ticket.raw_data["comments"]
    assert_equal 2, @ticket.raw_data["comments"].size
    assert_equal "This is the first comment", @ticket.raw_data["comments"][0]["body"]
    assert_equal "This is the second comment", @ticket.raw_data["comments"][1]["body"]
    assert_equal true, @ticket.raw_data["comments"][0]["public"]
    assert_equal false, @ticket.raw_data["comments"][1]["public"]
  end

  test "should handle missing ticket gracefully" do
    # Should not raise an error, just log a warning
    assert_nothing_raised do
      FetchTicketCommentsJob.perform_now(99999, @desk.id, "test.zendesk.com")
    end
  end

  test "should handle API errors gracefully" do
    stub_comments_api(12345, [], status: 500)

    assert_nothing_raised do
      FetchTicketCommentsJob.perform_now(12345, @desk.id, "test.zendesk.com")
    end

    @ticket.reload
    # Ticket should still exist, comments should not be updated
    assert_not_nil @ticket
    assert_nil @ticket.raw_data["comments"]
  end

  test "should handle rate limiting (429 error) with retry" do
    comments_data = [
      {
        id: 1,
        body: "Test comment",
        created_at: "2024-01-01T10:00:00Z"
      }
    ]

    # First call returns 429, second succeeds
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/12345/comments.json")
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
          body: {comments: comments_data}.to_json,
          headers: {"Content-Type" => "application/json"}
        }
      )

    assert_nothing_raised do
      FetchTicketCommentsJob.perform_now(12345, @desk.id, "test.zendesk.com")
    end

    @desk.reload
    # wait_till should be set from the rate limit
    assert_not_nil @desk.wait_till
    assert @desk.wait_till > 0

    @ticket.reload
    # Comments should be updated after retry
    assert_not_nil @ticket.raw_data["comments"]
    assert_equal 1, @ticket.raw_data["comments"].size
  end

  test "should handle empty comments response" do
    stub_comments_api(12345, [])

    FetchTicketCommentsJob.perform_now(12345, @desk.id, "test.zendesk.com")

    @ticket.reload
    # Should not crash, but comments may or may not be set
    assert_not_nil @ticket
  end

  test "should preserve existing raw_data when updating comments" do
    # Set some existing data in raw_data
    @ticket.update_columns(raw_data: {
      "id" => 12345,
      "subject" => "Test Ticket",
      "status" => "open",
      "priority" => "high",
      "custom_field" => "value"
    })

    comments_data = [
      {
        id: 1,
        body: "Test comment",
        created_at: "2024-01-01T10:00:00Z"
      }
    ]

    stub_comments_api(12345, comments_data)

    FetchTicketCommentsJob.perform_now(12345, @desk.id, "test.zendesk.com")

    @ticket.reload
    # Should preserve existing fields
    assert_equal "Test Ticket", @ticket.raw_data["subject"]
    assert_equal "open", @ticket.raw_data["status"]
    assert_equal "high", @ticket.raw_data["priority"]
    assert_equal "value", @ticket.raw_data["custom_field"]
    # Should add comments
    assert_not_nil @ticket.raw_data["comments"]
    assert_equal 1, @ticket.raw_data["comments"].size
  end

  test "should handle max retries on rate limit" do
    # Always return 429
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/12345/comments.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 429,
        headers: {
          "Retry-After" => "1"
        }
      )

    assert_nothing_raised do
      FetchTicketCommentsJob.perform_now(12345, @desk.id, "test.zendesk.com")
    end

    @ticket.reload
    # Comments should not be updated after max retries
    assert_nil @ticket.raw_data["comments"]
  end

  test "should handle network errors gracefully" do
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/12345/comments.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_raise(StandardError.new("Network error"))

    assert_nothing_raised do
      FetchTicketCommentsJob.perform_now(12345, @desk.id, "test.zendesk.com")
    end

    @ticket.reload
    # Ticket should still exist
    assert_not_nil @ticket
  end
end
