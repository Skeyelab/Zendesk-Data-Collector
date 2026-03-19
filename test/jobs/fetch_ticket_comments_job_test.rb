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

  def stub_comments_api(ticket_id, comments_data = [], status: 200)
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/#{ticket_id}/comments.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: status,
        body: {comments: comments_data}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
  end

  test "should fetch and store comments in zendesk_ticket_comments table" do
    comments_data = [
      {
        id: 1,
        type: "Comment",
        body: "This is the first comment",
        plain_body: "This is the first comment",
        public: true,
        author_id: 12_345,
        created_at: "2024-01-01T10:00:00Z"
      },
      {
        id: 2,
        type: "Comment",
        body: "This is the second comment",
        plain_body: "This is the second comment",
        public: false,
        author_id: 67_890,
        created_at: "2024-01-02T11:00:00Z"
      }
    ]

    stub_comments_api(12_345, comments_data)

    assert_difference "ZendeskTicketComment.count", 2 do
      FetchTicketCommentsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end

    first = ZendeskTicketComment.find_by(zendesk_comment_id: 1)
    second = ZendeskTicketComment.find_by(zendesk_comment_id: 2)

    assert_not_nil first
    assert_equal "This is the first comment", first.body
    assert_equal true, first.public

    assert_not_nil second
    assert_equal "This is the second comment", second.body
    assert_equal false, second.public
  end

  test "should strip comments from raw_data after persisting" do
    @ticket.update_columns(raw_data: @ticket.raw_data.merge("comments" => [{"id" => 99, "body" => "old"}]))

    comments_data = [{id: 1, body: "New comment", plain_body: "New comment", author_id: 1, created_at: "2024-01-01T10:00:00Z"}]
    stub_comments_api(12_345, comments_data)

    FetchTicketCommentsJob.perform_now(12_345, @desk.id, "test.zendesk.com")

    @ticket.reload
    assert_nil @ticket.raw_data["comments"]
  end

  test "should preserve other raw_data fields when updating comments" do
    @ticket.update_columns(raw_data: {
      "id" => 12_345,
      "subject" => "Test Ticket",
      "status" => "open",
      "priority" => "high",
      "custom_field" => "value"
    })

    comments_data = [{id: 1, body: "Test comment", plain_body: "Test comment", author_id: 1, created_at: "2024-01-01T10:00:00Z"}]
    stub_comments_api(12_345, comments_data)

    FetchTicketCommentsJob.perform_now(12_345, @desk.id, "test.zendesk.com")

    @ticket.reload
    assert_equal "Test Ticket", @ticket.raw_data["subject"]
    assert_equal "high", @ticket.raw_data["priority"]
    assert_equal "value", @ticket.raw_data["custom_field"]
    assert_nil @ticket.raw_data["comments"]
  end

  test "should handle missing ticket gracefully" do
    assert_nothing_raised do
      FetchTicketCommentsJob.perform_now(99_999, @desk.id, "test.zendesk.com")
    end
  end

  test "should handle API errors gracefully" do
    stub_comments_api(12_345, [], status: 500)

    assert_nothing_raised do
      FetchTicketCommentsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end

    assert_equal 0, ZendeskTicketComment.where(zendesk_ticket_id: @ticket.id).count
  end

  test "should handle empty comments response" do
    stub_comments_api(12_345, [])

    assert_no_difference "ZendeskTicketComment.count" do
      FetchTicketCommentsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end
  end

  test "should handle rate limiting (429 error) with retry" do
    comments_data = [{id: 1, body: "Test comment", plain_body: "Test comment", author_id: 1, created_at: "2024-01-01T10:00:00Z"}]

    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/12345/comments.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        {status: 429, headers: {"Retry-After" => "1"}},
        {status: 200, body: {comments: comments_data}.to_json, headers: {"Content-Type" => "application/json"}}
      )

    assert_nothing_raised do
      FetchTicketCommentsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end

    @desk.reload
    assert_not_nil @desk.wait_till
    assert @desk.wait_till > 0
    assert_equal 1, ZendeskTicketComment.where(zendesk_ticket_id: @ticket.id).count
  end

  test "should handle max retries on rate limit" do
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/12345/comments.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(status: 429, headers: {"Retry-After" => "1"})

    assert_nothing_raised do
      FetchTicketCommentsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end

    assert_equal 0, ZendeskTicketComment.where(zendesk_ticket_id: @ticket.id).count
  end

  test "should handle network errors gracefully" do
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/12345/comments.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_raise(StandardError.new("Network error"))

    assert_nothing_raised do
      FetchTicketCommentsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end
  end

  test "should upsert on re-fetch (idempotent)" do
    comments_data = [{id: 1, body: "Original body", plain_body: "Original body", author_id: 1, created_at: "2024-01-01T10:00:00Z"}]
    stub_comments_api(12_345, comments_data)
    FetchTicketCommentsJob.perform_now(12_345, @desk.id, "test.zendesk.com")

    updated_comments = [{id: 1, body: "Updated body", plain_body: "Updated body", author_id: 1, created_at: "2024-01-01T10:00:00Z"}]
    stub_comments_api(12_345, updated_comments)

    assert_no_difference "ZendeskTicketComment.count" do
      FetchTicketCommentsJob.perform_now(12_345, @desk.id, "test.zendesk.com")
    end
  end
end
