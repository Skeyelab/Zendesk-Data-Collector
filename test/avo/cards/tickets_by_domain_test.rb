require "test_helper"

class Avo::Cards::TicketsByDomainTest < ActiveSupport::TestCase
  def setup
    # Clean up any existing tickets
    ZendeskTicket.delete_all
  end

  test "should return empty hash when no tickets exist" do
    card = Avo::Cards::TicketsByDomain.new
    result = card.query

    assert_equal({}, result)
  end

  test "should group tickets by domain correctly" do
    create_zendesk_ticket(zendesk_id: 1, domain: "domain1.zendesk.com")
    create_zendesk_ticket(zendesk_id: 2, domain: "domain1.zendesk.com")
    create_zendesk_ticket(zendesk_id: 3, domain: "domain2.zendesk.com")

    card = Avo::Cards::TicketsByDomain.new
    result = card.query

    expected = {
      "domain1.zendesk.com" => 2,
      "domain2.zendesk.com" => 1
    }
    assert_equal expected, result
  end

  test "should handle multiple domains with single tickets" do
    create_zendesk_ticket(zendesk_id: 1, domain: "domain1.zendesk.com")
    create_zendesk_ticket(zendesk_id: 2, domain: "domain2.zendesk.com")
    create_zendesk_ticket(zendesk_id: 3, domain: "domain3.zendesk.com")

    card = Avo::Cards::TicketsByDomain.new
    result = card.query

    expected = {
      "domain1.zendesk.com" => 1,
      "domain2.zendesk.com" => 1,
      "domain3.zendesk.com" => 1
    }
    assert_equal expected, result
  end

  test "should count tickets accurately for each domain" do
    # Domain 1: 3 tickets
    create_zendesk_ticket(zendesk_id: 1, domain: "domain1.zendesk.com")
    create_zendesk_ticket(zendesk_id: 2, domain: "domain1.zendesk.com")
    create_zendesk_ticket(zendesk_id: 3, domain: "domain1.zendesk.com")

    # Domain 2: 1 ticket
    create_zendesk_ticket(zendesk_id: 4, domain: "domain2.zendesk.com")

    # Domain 3: 2 tickets
    create_zendesk_ticket(zendesk_id: 5, domain: "domain3.zendesk.com")
    create_zendesk_ticket(zendesk_id: 6, domain: "domain3.zendesk.com")

    card = Avo::Cards::TicketsByDomain.new
    result = card.query

    expected = {
      "domain1.zendesk.com" => 3,
      "domain2.zendesk.com" => 1,
      "domain3.zendesk.com" => 2
    }
    assert_equal expected, result
  end

  test "should return hash with string keys and integer values" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com")

    card = Avo::Cards::TicketsByDomain.new
    result = card.query

    assert_kind_of Hash, result
    assert_kind_of String, result.keys.first
    assert_kind_of Integer, result.values.first
  end

  private

  def create_zendesk_ticket(zendesk_id:, domain:)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: domain,
      subject: "Test Ticket #{zendesk_id}",
      status: "open"
    )
  end
end
