require "test_helper"

class ZendeskTicketUpsertServiceTest < ActiveSupport::TestCase
  test "creates a new ticket and returns :created" do
    ticket_hash = {
      "id" => 42,
      "subject" => "New ticket",
      "status" => "open",
      "priority" => "normal"
    }
    domain = "support.example.com"

    result = ZendeskTicketUpsertService.call(ticket_hash, domain)

    assert_equal :created, result
    record = ZendeskTicket.find_by(zendesk_id: 42, domain: domain)
    assert record
    assert_equal "New ticket", record.subject
    assert_equal "open", record.status
  end

  test "updates existing ticket and returns :updated" do
    ZendeskTicket.create!(
      zendesk_id: 99,
      domain: "support.example.com",
      subject: "Old subject",
      status: "open"
    )

    ticket_hash = {
      "id" => 99,
      "subject" => "Updated subject",
      "status" => "solved",
      "priority" => "high"
    }
    domain = "support.example.com"

    result = ZendeskTicketUpsertService.call(ticket_hash, domain)

    assert_equal :updated, result
    record = ZendeskTicket.find_by(zendesk_id: 99, domain: domain)
    assert_equal "Updated subject", record.subject
    assert_equal "solved", record.status
    assert_equal 1, ZendeskTicket.where(zendesk_id: 99, domain: domain).count
  end

  test "accepts symbol keys for id" do
    ticket_hash = {id: 100, subject: "Symbol id", status: "new"}
    result = ZendeskTicketUpsertService.call(ticket_hash, "support.example.com")
    assert_equal :created, result
    assert ZendeskTicket.exists?(zendesk_id: 100, domain: "support.example.com")
  end

  test "sets domain on ticket from second argument when missing in hash" do
    ticket_hash = {"id" => 101, "subject" => "No domain in hash", "status" => "open"}
    ZendeskTicketUpsertService.call(ticket_hash, "desk.zendesk.com")
    record = ZendeskTicket.find_by(zendesk_id: 101, domain: "desk.zendesk.com")
    assert record
    assert_equal "desk.zendesk.com", record.domain
  end

  test "raises on invalid data" do
    ticket_hash = {"id" => nil, "subject" => "Bad"}
    assert_raises(ActiveRecord::RecordInvalid) do
      ZendeskTicketUpsertService.call(ticket_hash, "desk.zendesk.com")
    end
  end
end
