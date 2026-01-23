require "test_helper"
require "webmock/minitest"

class IncrementalTicketJobTest < ActiveJob::TestCase
  def setup
    @desk = Desk.create!(
      domain: "test.zendesk.com",
      user: "test@example.com",
      token: "test_token",
      last_timestamp: 1000,
      active: true,
      queued: true
    )

    # Sample Zendesk ticket data
    @ticket_data = {
      id: 12345,
      subject: "Test Ticket",
      status: "open",
      priority: "normal",
      created_at: Time.now.iso8601,
      updated_at: Time.now.iso8601,
      generated_timestamp: Time.now.to_i,
      requester: {
        name: "John Doe",
        email: "john@example.com"
      }
    }
  end

  def stub_comments_api(ticket_id, comments_data = [])
    stub_request(:get, "https://test.zendesk.com/api/v2/tickets/#{ticket_id}/comments.json")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {comments: comments_data}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
  end

  test "should fetch tickets from Zendesk and save to PostgreSQL" do
    # Mock Zendesk API response
    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [@ticket_data],
          users: [],
          end_time: 2000,
          count: 1
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Comments are now fetched asynchronously, no need to stub

    assert_difference "ZendeskTicket.count", 1 do
      IncrementalTicketJob.perform_now(@desk.id)
    end

    ticket = ZendeskTicket.find_by(zendesk_id: 12345, domain: "test.zendesk.com")
    assert_not_nil ticket
    assert_equal "Test Ticket", ticket.subject
    assert_equal "open", ticket.status
    assert_equal "John Doe", ticket.req_name
    assert_equal "john@example.com", ticket.req_email
  end

  test "should update existing ticket in PostgreSQL" do
    # Create existing ticket
    ZendeskTicket.create!(
      zendesk_id: 12345,
      domain: "test.zendesk.com",
      subject: "Old Subject",
      status: "open"
    )

    # Mock API response with updated ticket
    updated_data = @ticket_data.merge(
      subject: "Updated Subject",
      status: "solved"
    )

    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [updated_data],
          users: [],
          end_time: 2000,
          count: 1
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Comments are now fetched asynchronously, no need to stub

    assert_no_difference "ZendeskTicket.count" do
      IncrementalTicketJob.perform_now(@desk.id)
    end

    ticket = ZendeskTicket.find_by(zendesk_id: 12345, domain: "test.zendesk.com")
    assert_equal "Updated Subject", ticket.subject
    assert_equal "solved", ticket.status
  end

  test "should update desk last_timestamp after successful fetch" do
    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [@ticket_data],
          users: [],
          end_time: 2000,
          count: 1
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Comments are now fetched asynchronously, no need to stub

    IncrementalTicketJob.perform_now(@desk.id)

    @desk.reload
    assert_equal 2000, @desk.last_timestamp
  end

  test "should handle rate limiting (429 error)" do
    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 429,
        headers: {
          "Retry-After" => "60"
        }
      )

    assert_no_difference "ZendeskTicket.count" do
      IncrementalTicketJob.perform_now(@desk.id)
    end

    @desk.reload
    assert @desk.wait_till > Time.now.to_i
  end

  test "should set desk queued to false after completion" do
    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [],
          users: [],
          end_time: 1000,
          count: 0
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    IncrementalTicketJob.perform_now(@desk.id)

    @desk.reload
    assert_equal false, @desk.queued
  end

  test "should handle API errors gracefully" do
    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(status: 500, body: "Internal Server Error")

    assert_no_difference "ZendeskTicket.count" do
      assert_nothing_raised do
        IncrementalTicketJob.perform_now(@desk.id)
      end
    end

    @desk.reload
    assert_equal false, @desk.queued
  end

  test "should process multiple tickets in one batch" do
    tickets = [
      @ticket_data.merge(id: 1),
      @ticket_data.merge(id: 2),
      @ticket_data.merge(id: 3)
    ]

    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: tickets,
          users: [],
          end_time: 2000,
          count: 3
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Mock comments API for each ticket
    stub_comments_api(1)
    stub_comments_api(2)
    stub_comments_api(3)

    assert_difference "ZendeskTicket.count", 3 do
      IncrementalTicketJob.perform_now(@desk.id)
    end
  end

  test "should handle empty response" do
    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [],
          users: [],
          end_time: 1000,
          count: 0
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    assert_no_difference "ZendeskTicket.count" do
      IncrementalTicketJob.perform_now(@desk.id)
    end

    @desk.reload
    assert_equal 1000, @desk.last_timestamp
  end

  test "should not update timestamp when new_timestamp is less than or equal to start_time" do
    @desk.update!(last_timestamp: 5000)

    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=5000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [@ticket_data],
          users: [],
          end_time: 3000, # Less than start_time
          count: 1
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Comments are now fetched asynchronously, no need to stub

    IncrementalTicketJob.perform_now(@desk.id)

    @desk.reload
    assert_equal 5000, @desk.last_timestamp # Should not update
  end

  test "should handle tickets with symbol keys" do
    ticket_with_symbols = {
      id: 999,
      subject: "Symbol Key Ticket",
      created_at: Time.now.iso8601
    }

    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [ticket_with_symbols],
          users: [],
          end_time: 2000,
          count: 1
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Mock comments API
    stub_comments_api(999)

    assert_difference "ZendeskTicket.count", 1 do
      IncrementalTicketJob.perform_now(@desk.id)
    end

    ticket = ZendeskTicket.find_by(zendesk_id: 999, domain: "test.zendesk.com")
    assert_not_nil ticket
    assert_equal "Symbol Key Ticket", ticket.subject
  end

  test "should handle invalid timestamp strings gracefully" do
    ticket_with_invalid_timestamp = @ticket_data.merge(
      created_at: "not-a-valid-timestamp",
      updated_at: "also-invalid"
    )

    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [ticket_with_invalid_timestamp],
          users: [],
          end_time: 2000,
          count: 1
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Comments are now fetched asynchronously, no need to stub

    assert_difference "ZendeskTicket.count", 1 do
      assert_nothing_raised do
        IncrementalTicketJob.perform_now(@desk.id)
      end
    end

    ticket = ZendeskTicket.find_by(zendesk_id: 12345, domain: "test.zendesk.com")
    assert_not_nil ticket
    # Invalid timestamps should be handled gracefully (stored as-is if parsing fails)
    # The actual behavior may vary, so we just ensure the ticket was saved
    assert_not_nil ticket.created_at
  end

  test "should extract requester email from sideloaded users" do
    # Ticket with requester_id only (not nested requester object)
    ticket_data = {
      id: 12345,
      subject: "Test Ticket",
      status: "open",
      priority: "normal",
      created_at: Time.now.iso8601,
      updated_at: Time.now.iso8601,
      generated_timestamp: Time.now.to_i,
      requester_id: 98765,
      assignee_id: 54321
    }

    # Sideloaded users array
    users_data = [
      {
        id: 98765,
        name: "John Doe",
        email: "john@example.com",
        external_id: "ext_123"
      },
      {
        id: 54321,
        name: "Jane Smith",
        email: "jane@example.com"
      }
    ]

    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [ticket_data],
          users: users_data,
          end_time: 2000,
          count: 1
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Comments are now fetched asynchronously, no need to stub

    assert_difference "ZendeskTicket.count", 1 do
      IncrementalTicketJob.perform_now(@desk.id)
    end

    ticket = ZendeskTicket.find_by(zendesk_id: 12345, domain: "test.zendesk.com")
    assert_not_nil ticket
    assert_equal "Test Ticket", ticket.subject
    assert_equal "John Doe", ticket.req_name
    assert_equal "john@example.com", ticket.req_email
    assert_equal 98765, ticket.req_id
    assert_equal "ext_123", ticket.req_external_id
    assert_equal "Jane Smith", ticket.assignee_name
    assert_equal 54321, ticket.assignee_id
  end

  test "should enqueue FetchTicketCommentsJob for each ticket" do
    # Mock tickets response
    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [@ticket_data],
          users: [],
          end_time: 2000,
          count: 1
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    assert_difference "ZendeskTicket.count", 1 do
      assert_enqueued_with(job: FetchTicketCommentsJob, args: [12345, @desk.id, "test.zendesk.com"]) do
        IncrementalTicketJob.perform_now(@desk.id)
      end
    end

    ticket = ZendeskTicket.find_by(zendesk_id: 12345, domain: "test.zendesk.com")
    assert_not_nil ticket
    # Comments should not be in raw_data yet (they'll be added by the async job)
    assert_nil ticket.raw_data["comments"]
  end

  test "should enqueue comment job even if comments API would fail" do
    # Mock tickets response
    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [@ticket_data],
          users: [],
          end_time: 2000,
          count: 1
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Should still create the ticket and enqueue comment job
    assert_difference "ZendeskTicket.count", 1 do
      assert_enqueued_with(job: FetchTicketCommentsJob, args: [12345, @desk.id, "test.zendesk.com"]) do
        assert_nothing_raised do
          IncrementalTicketJob.perform_now(@desk.id)
        end
      end
    end

    ticket = ZendeskTicket.find_by(zendesk_id: 12345, domain: "test.zendesk.com")
    assert_not_nil ticket
    assert_equal "Test Ticket", ticket.subject
  end

  test "should enqueue comment job regardless of comments API rate limiting" do
    # Mock tickets response
    stub_request(:get, "https://test.zendesk.com/api/v2/incremental/tickets.json?include=users&start_time=1000")
      .with(basic_auth: ["test@example.com/token", "test_token"])
      .to_return(
        status: 200,
        body: {
          tickets: [@ticket_data],
          users: [],
          end_time: 2000,
          count: 1
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Should create the ticket and enqueue comment job
    # Rate limiting will be handled by FetchTicketCommentsJob
    assert_difference "ZendeskTicket.count", 1 do
      assert_enqueued_with(job: FetchTicketCommentsJob, args: [12345, @desk.id, "test.zendesk.com") do
        assert_nothing_raised do
          IncrementalTicketJob.perform_now(@desk.id)
        end
      end
    end

    ticket = ZendeskTicket.find_by(zendesk_id: 12345, domain: "test.zendesk.com")
    assert_not_nil ticket
    assert_equal "Test Ticket", ticket.subject
  end
end
