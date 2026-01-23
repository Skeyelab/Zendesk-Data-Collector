require "test_helper"

class Avo::Cards::TotalTicketsCountTest < ActiveSupport::TestCase
  def setup
    # Clean up any existing tickets
    ZendeskTicket.delete_all
  end

  test "should return zero when no tickets exist" do
    card = Avo::Cards::TotalTicketsCount.new
    result = card.query

    assert_equal 0, result
  end

  test "should return correct count when tickets exist" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test1.zendesk.com")
    create_zendesk_ticket(zendesk_id: 2, domain: "test2.zendesk.com")

    card = Avo::Cards::TotalTicketsCount.new
    result = card.query

    assert_equal 2, result
  end

  test "should count tickets from all domains" do
    create_zendesk_ticket(zendesk_id: 1, domain: "domain1.zendesk.com")
    create_zendesk_ticket(zendesk_id: 2, domain: "domain1.zendesk.com")
    create_zendesk_ticket(zendesk_id: 3, domain: "domain2.zendesk.com")

    card = Avo::Cards::TotalTicketsCount.new
    result = card.query

    assert_equal 3, result
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
