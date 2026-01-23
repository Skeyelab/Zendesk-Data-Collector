require "test_helper"

class Avo::Cards::TicketsByPriorityTest < ActiveSupport::TestCase
  def setup
    # Clean up any existing tickets
    ZendeskTicket.delete_all
  end

  test "should return empty hash when no tickets exist" do
    card = Avo::Cards::TicketsByPriority.new
    result = card.query

    assert_equal({}, result)
  end

  test "should group tickets by priority correctly" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", priority: "urgent")
    create_zendesk_ticket(zendesk_id: 2, domain: "test.zendesk.com", priority: "high")
    create_zendesk_ticket(zendesk_id: 3, domain: "test.zendesk.com", priority: "high")
    create_zendesk_ticket(zendesk_id: 4, domain: "test.zendesk.com", priority: "normal")

    card = Avo::Cards::TicketsByPriority.new
    result = card.query

    expected = {
      "urgent" => 1,
      "high" => 2,
      "normal" => 1
    }
    assert_equal expected, result
  end

  test "should include all priority types that exist in data" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", priority: "low")

    card = Avo::Cards::TicketsByPriority.new
    result = card.query

    expected = {
      "low" => 1
    }
    assert_equal expected, result
  end

  test "should count tickets from all domains together" do
    create_zendesk_ticket(zendesk_id: 1, domain: "domain1.zendesk.com", priority: "urgent")
    create_zendesk_ticket(zendesk_id: 2, domain: "domain2.zendesk.com", priority: "urgent")
    create_zendesk_ticket(zendesk_id: 3, domain: "domain1.zendesk.com", priority: "normal")

    card = Avo::Cards::TicketsByPriority.new
    result = card.query

    expected = {
      "urgent" => 2,
      "normal" => 1
    }
    assert_equal expected, result
  end

  test "should return hash with string keys and integer values" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", priority: "urgent")

    card = Avo::Cards::TicketsByPriority.new
    result = card.query

    assert_kind_of Hash, result
    assert_kind_of String, result.keys.first
    assert_kind_of Integer, result.values.first
  end

  private

  def create_zendesk_ticket(zendesk_id:, domain:, priority:)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: domain,
      subject: "Test Ticket #{zendesk_id}",
      priority: priority
    )
  end
end
