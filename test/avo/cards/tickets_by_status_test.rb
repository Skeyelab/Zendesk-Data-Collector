require "test_helper"

class Avo::Cards::TicketsByStatusTest < ActiveSupport::TestCase
  def setup
    # Clean up any existing tickets
    ZendeskTicket.delete_all
  end

  test "should return empty hash when no tickets exist" do
    card = Avo::Cards::TicketsByStatus.new
    result = card.query

    assert_equal({}, result)
  end

  test "should group tickets by status correctly" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", status: "new")
    create_zendesk_ticket(zendesk_id: 2, domain: "test.zendesk.com", status: "open")
    create_zendesk_ticket(zendesk_id: 3, domain: "test.zendesk.com", status: "open")
    create_zendesk_ticket(zendesk_id: 4, domain: "test.zendesk.com", status: "solved")

    card = Avo::Cards::TicketsByStatus.new
    result = card.query

    expected = {
      "new" => 1,
      "open" => 2,
      "solved" => 1
    }
    assert_equal expected, result
  end

  test "should include all status types that exist in data" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", status: "pending")
    create_zendesk_ticket(zendesk_id: 2, domain: "test.zendesk.com", status: "closed")

    card = Avo::Cards::TicketsByStatus.new
    result = card.query

    expected = {
      "pending" => 1,
      "closed" => 1
    }
    assert_equal expected, result
  end

  test "should count tickets from all domains together" do
    create_zendesk_ticket(zendesk_id: 1, domain: "domain1.zendesk.com", status: "open")
    create_zendesk_ticket(zendesk_id: 2, domain: "domain2.zendesk.com", status: "open")
    create_zendesk_ticket(zendesk_id: 3, domain: "domain1.zendesk.com", status: "solved")

    card = Avo::Cards::TicketsByStatus.new
    result = card.query

    expected = {
      "open" => 2,
      "solved" => 1
    }
    assert_equal expected, result
  end

  test "should return hash with string keys and integer values" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", status: "open")

    card = Avo::Cards::TicketsByStatus.new
    result = card.query

    assert_kind_of Hash, result
    assert_kind_of String, result.keys.first
    assert_kind_of Integer, result.values.first
  end

  private

  def create_zendesk_ticket(zendesk_id:, domain:, status:)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: domain,
      subject: "Test Ticket #{zendesk_id}",
      status: status
    )
  end
end
