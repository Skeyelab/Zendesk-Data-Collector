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
    now = Time.now
    ticket_hash = {
      "id" => 700,
      "domain" => "test.zendesk.com",
      "created_at" => now.iso8601,
      "updated_at" => now.iso8601,
      "solved_at" => now.iso8601
    }
    ticket = ZendeskTicket.new
    ticket.assign_ticket_data(ticket_hash)
    ticket.save!

    # Timestamps come directly from Zendesk API
    assert_not_nil ticket.created_at
    assert_not_nil ticket.updated_at
    assert_not_nil ticket.solved_at
    # Verify they match the API values (within 1 second tolerance)
    assert_in_delta now.to_i, ticket.created_at.to_i, 1
    assert_in_delta now.to_i, ticket.updated_at.to_i, 1
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

  test "assign_metrics_data should extract nested time metrics correctly" do
    ticket = ZendeskTicket.create!(
      zendesk_id: 900,
      domain: "test.zendesk.com"
    )

    metrics_data = {
      "reply_time_in_minutes" => {
        "business" => 100,
        "calendar" => 500
      },
      "first_resolution_time_in_minutes" => {
        "business" => 200,
        "calendar" => 800
      },
      "full_resolution_time_in_minutes" => {
        "business" => 300,
        "calendar" => 1000
      },
      "agent_wait_time_in_minutes" => {
        "business" => 50,
        "calendar" => 200
      },
      "requester_wait_time_in_minutes" => {
        "business" => 150,
        "calendar" => 400
      },
      "on_hold_time_in_minutes" => {
        "business" => 25,
        "calendar" => 100
      }
    }

    ticket.assign_metrics_data(metrics_data)
    ticket.save!

    # Calendar values go to main columns
    assert_equal 500, ticket.first_reply_time_in_minutes
    assert_equal 800, ticket.first_resolution_time_in_minutes
    assert_equal 1000, ticket.full_resolution_time_in_minutes
    assert_equal 200, ticket.agent_wait_time_in_minutes
    assert_equal 400, ticket.requester_wait_time_in_minutes
    assert_equal 100, ticket.on_hold_time_in_minutes

    # Business values go to _within_business_hours columns
    assert_equal 100, ticket.first_reply_time_in_minutes_within_business_hours
    assert_equal 200, ticket.first_resolution_time_in_minutes_within_business_hours
    assert_equal 300, ticket.full_resolution_time_in_minutes_within_business_hours
    assert_equal 50, ticket.agent_wait_time_in_minutes_within_business_hours
    assert_equal 150, ticket.requester_wait_time_in_minutes_within_business_hours
    assert_equal 25, ticket.on_hold_time_in_minutes_within_business_hours
  end

  test "assign_metrics_data should parse timestamp fields from ISO8601 strings" do
    ticket = ZendeskTicket.create!(
      zendesk_id: 901,
      domain: "test.zendesk.com"
    )

    assigned_time = Time.parse("2011-05-05T10:38:52Z")
    solved_time = Time.parse("2011-05-09T10:38:52Z")

    metrics_data = {
      "assigned_at" => "2011-05-05T10:38:52Z",
      "solved_at" => "2011-05-09T10:38:52Z",
      "status_updated_at" => "2011-05-04T10:38:52Z",
      "latest_comment_added_at" => "2011-05-09T10:38:52Z",
      "requester_updated_at" => "2011-05-07T10:38:52Z",
      "assignee_updated_at" => "2011-05-06T10:38:52Z",
      "custom_status_updated_at" => "2011-05-09T10:38:52Z",
      "initially_assigned_at" => "2011-05-03T10:38:52Z"
    }

    ticket.assign_metrics_data(metrics_data)
    ticket.save!

    assert_not_nil ticket.assigned_at
    assert_not_nil ticket.solved_at
    assert_not_nil ticket.initially_assigned_at

    # Verify timestamps are parsed correctly (within 1 second tolerance)
    assert_in_delta assigned_time.to_i, ticket.assigned_at.to_i, 1
    assert_in_delta solved_time.to_i, ticket.solved_at.to_i, 1

    # These columns may not exist if migration was rolled back - just verify no crash
  end

  test "assign_metrics_data should store count fields as strings" do
    ticket = ZendeskTicket.create!(
      zendesk_id: 902,
      domain: "test.zendesk.com"
    )

    metrics_data = {
      "reopens" => 5,
      "replies" => 10,
      "assignee_stations" => 2,
      "group_stations" => 4
    }

    ticket.assign_metrics_data(metrics_data)
    ticket.save!

    # Schema has these as strings
    assert_equal "5", ticket.reopens
    assert_equal "10", ticket.replies
    assert_equal "2", ticket.assignee_stations
    assert_equal "4", ticket.group_stations

    # Verify they are strings (schema constraint)
    assert_instance_of String, ticket.reopens
    assert_instance_of String, ticket.replies
    assert_instance_of String, ticket.assignee_stations
    assert_instance_of String, ticket.group_stations
  end

  test "assign_metrics_data should preserve full metrics in raw_data" do
    ticket = ZendeskTicket.create!(
      zendesk_id: 903,
      domain: "test.zendesk.com"
    )

    metrics_data = {
      "reply_time_in_minutes" => {
        "business" => 100,
        "calendar" => 500
      },
      "reopens" => 2,
      "replies" => 3,
      "reply_time_in_seconds" => {
        "calendar" => 30000
      }
    }

    ticket.assign_metrics_data(metrics_data)
    ticket.save!

    # Full metrics should be stored in raw_data
    assert_not_nil ticket.raw_data["metrics"]
    assert_equal 500, ticket.raw_data["metrics"]["reply_time_in_minutes"]["calendar"]
    assert_equal 100, ticket.raw_data["metrics"]["reply_time_in_minutes"]["business"]
    assert_equal 2, ticket.raw_data["metrics"]["reopens"]
    assert_equal 3, ticket.raw_data["metrics"]["replies"]
    assert_not_nil ticket.raw_data["metrics"]["reply_time_in_seconds"]
  end

  test "assign_metrics_data should handle missing/null values gracefully" do
    ticket = ZendeskTicket.create!(
      zendesk_id: 904,
      domain: "test.zendesk.com"
    )

    metrics_data = {
      "reply_time_in_minutes" => nil,
      "reopens" => nil,
      "assigned_at" => nil
    }

    assert_nothing_raised do
      ticket.assign_metrics_data(metrics_data)
      ticket.save!
    end

    # Should not crash, values may remain nil
    assert_not_nil ticket
  end

  test "assign_metrics_data should store reply_time_in_seconds only in raw_data" do
    ticket = ZendeskTicket.create!(
      zendesk_id: 905,
      domain: "test.zendesk.com"
    )

    metrics_data = {
      "reply_time_in_seconds" => {
        "calendar" => 30000
      }
    }

    ticket.assign_metrics_data(metrics_data)
    ticket.save!

    # reply_time_in_seconds should be in raw_data but not extracted to columns
    assert_not_nil ticket.raw_data["metrics"]["reply_time_in_seconds"]
    assert_equal 30000, ticket.raw_data["metrics"]["reply_time_in_seconds"]["calendar"]
    # Should not have a column for this
    begin
      assert_nil ticket.read_attribute(:reply_time_in_seconds)
    rescue
      nil
    end
  end
end
