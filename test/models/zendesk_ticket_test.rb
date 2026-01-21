require "test_helper"

class ZendeskTicketTest < ActiveSupport::TestCase
  def setup
    @ticket_data = {
      zendesk_id: 12345,
      domain: "test.zendesk.com",
      subject: "Test Ticket",
      status: "open",
      priority: "normal",
      generated_timestamp: Time.now.to_i
    }
  end

  test "should create ticket with required fields" do
    ticket = ZendeskTicket.create!(@ticket_data)
    assert ticket.persisted?
    assert_equal 12345, ticket.zendesk_id
    assert_equal "test.zendesk.com", ticket.domain
    assert_equal "Test Ticket", ticket.subject
  end

  test "should require zendesk_id field" do
    @ticket_data.delete(:zendesk_id)
    ticket = ZendeskTicket.new(@ticket_data)
    assert_not ticket.valid?
    assert_includes ticket.errors[:zendesk_id], "can't be blank"
  end

  test "should require domain field" do
    @ticket_data.delete(:domain)
    ticket = ZendeskTicket.new(@ticket_data)
    assert_not ticket.valid?
    assert_includes ticket.errors[:domain], "can't be blank"
  end

  test "should allow dynamic fields from Zendesk API via raw_data" do
    ticket_hash = {
      "id" => 12345,
      "domain" => "test.zendesk.com",
      "subject" => "Test Ticket",
      "status" => "open",
      "req_name" => "John Doe",
      "req_email" => "john@example.com",
      "assignee_name" => "Jane Smith",
      "tags" => ["urgent", "important"],
      "first_reply_time_in_minutes" => 30,
      "custom_field_123" => "custom_value"
    }
    ticket = ZendeskTicket.new
    ticket.assign_ticket_data(ticket_hash)
    ticket.save!

    assert_equal "John Doe", ticket.req_name
    assert_equal "john@example.com", ticket.req_email
    assert_equal "Jane Smith", ticket.assignee_name
    assert_equal "urgent,important", ticket.current_tags
    assert_equal 30, ticket.first_reply_time_in_minutes
    # Access custom field via raw_data
    assert_equal "custom_value", ticket.raw_data["custom_field_123"]
  end

  test "should upsert based on zendesk_id and domain" do
    # Create initial ticket
    ZendeskTicket.create!(
      zendesk_id: 999,
      domain: "test.zendesk.com",
      subject: "Original Subject",
      status: "open"
    )

    # Upsert with same id and domain
    ticket2 = ZendeskTicket.find_or_initialize_by(
      zendesk_id: 999,
      domain: "test.zendesk.com"
    )
    ticket2.subject = "Updated Subject"
    ticket2.status = "solved"
    ticket2.save!

    # Should only be one ticket
    assert_equal 1, ZendeskTicket.where(zendesk_id: 999, domain: "test.zendesk.com").count
    updated_ticket = ZendeskTicket.find_by(zendesk_id: 999, domain: "test.zendesk.com")
    assert_equal "Updated Subject", updated_ticket.subject
    assert_equal "solved", updated_ticket.status
  end

  test "should allow multiple tickets with same zendesk_id for different domains" do
    ticket1 = ZendeskTicket.create!(
      zendesk_id: 100,
      domain: "domain1.zendesk.com",
      subject: "Ticket 1"
    )

    ticket2 = ZendeskTicket.create!(
      zendesk_id: 100,
      domain: "domain2.zendesk.com",
      subject: "Ticket 2"
    )

    assert ticket1.persisted?
    assert ticket2.persisted?
    assert_equal 2, ZendeskTicket.where(zendesk_id: 100).count
  end

  test "should index by domain for efficient queries" do
    ZendeskTicket.create!(
      zendesk_id: 1,
      domain: "test.zendesk.com",
      subject: "Test 1"
    )
    ZendeskTicket.create!(
      zendesk_id: 2,
      domain: "test.zendesk.com",
      subject: "Test 2"
    )
    ZendeskTicket.create!(
      zendesk_id: 3,
      domain: "other.zendesk.com",
      subject: "Other"
    )

    test_tickets = ZendeskTicket.where(domain: "test.zendesk.com")
    assert_equal 2, test_tickets.count
    assert test_tickets.all? { |t| t.domain == "test.zendesk.com" }
  end

  test "should handle timestamp fields" do
    now = Time.now
    ticket = ZendeskTicket.create!(
      zendesk_id: 200,
      domain: "test.zendesk.com",
      generated_timestamp: now.to_i
    )

    assert_equal now.to_i, ticket.generated_timestamp
    assert_not_nil ticket.created_at
    assert_not_nil ticket.updated_at
  end

  test "should handle integer fields" do
    ticket = ZendeskTicket.create!(
      zendesk_id: 300,
      domain: "test.zendesk.com",
      first_reply_time_in_minutes: 45,
      first_resolution_time_in_minutes: 120,
      assignee_id: 12345
    )

    assert_equal 45, ticket.first_reply_time_in_minutes
    assert_equal 120, ticket.first_resolution_time_in_minutes
    assert_equal 12345, ticket.assignee_id
  end

  test "should handle string fields with various lengths" do
    ticket = ZendeskTicket.create!(
      zendesk_id: 400,
      domain: "test.zendesk.com",
      req_name: "Short Name",
      current_tags: "tag1,tag2,tag3," * 50, # Long string
      url: "https://test.zendesk.com/api/v2/tickets/400.json"
    )

    assert_equal "Short Name", ticket.req_name
    assert ticket.current_tags.length > 255
    assert ticket.url.present?
  end

  test "should extract requester fields from nested hash" do
    ticket_hash = {
      "id" => 500,
      "domain" => "test.zendesk.com",
      "requester" => {
        "name" => "John Doe",
        "email" => "john@example.com",
        "id" => 123,
        "external_id" => "ext_123"
      }
    }
    ticket = ZendeskTicket.new
    ticket.assign_ticket_data(ticket_hash)
    ticket.save!

    assert_equal "John Doe", ticket.req_name
    assert_equal "john@example.com", ticket.req_email
    assert_equal 123, ticket.req_id
    assert_equal "ext_123", ticket.req_external_id
  end

  test "should extract assignee fields from nested hash" do
    ticket_hash = {
      "id" => 600,
      "domain" => "test.zendesk.com",
      "assignee" => {
        "name" => "Jane Smith",
        "id" => 456,
        "external_id" => 789
      }
    }
    ticket = ZendeskTicket.new
    ticket.assign_ticket_data(ticket_hash)
    ticket.save!

    assert_equal "Jane Smith", ticket.assignee_name
    assert_equal 456, ticket.assignee_id
    assert_equal 789, ticket.assignee_external_id
  end

  test "should parse time fields from strings" do
    ticket_hash = {
      "id" => 700,
      "domain" => "test.zendesk.com",
      "created_at" => Time.now.iso8601,
      "updated_at" => Time.now.iso8601,
      "solved_at" => Time.now.iso8601
    }
    ticket = ZendeskTicket.new
    ticket.assign_ticket_data(ticket_hash)
    ticket.save!

    assert_not_nil ticket.created_at
    assert_not_nil ticket.updated_at
    assert_not_nil ticket.solved_at
  end

  test "should store complete raw data in JSONB" do
    ticket_hash = {
      "id" => 800,
      "domain" => "test.zendesk.com",
      "subject" => "Test",
      "custom_field_1" => "value1",
      "custom_field_2" => {"nested" => "value"}
    }
    ticket = ZendeskTicket.new
    ticket.assign_ticket_data(ticket_hash)
    ticket.save!

    assert_equal "value1", ticket.raw_data["custom_field_1"]
    assert_equal({"nested" => "value"}, ticket.raw_data["custom_field_2"])
  end
end
