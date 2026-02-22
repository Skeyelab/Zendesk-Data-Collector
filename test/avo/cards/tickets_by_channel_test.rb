require "test_helper"

class Avo::Cards::TicketsByChannelTest < ActiveSupport::TestCase
  def setup
    ZendeskTicket.delete_all
  end

  test "should return empty hash when no tickets exist" do
    card = Avo::Cards::TicketsByChannel.new
    assert_equal({}, card.query)
  end

  test "should group tickets by channel" do
    create_ticket(1, "email")
    create_ticket(2, "email")
    create_ticket(3, "web")

    card = Avo::Cards::TicketsByChannel.new
    result = card.query

    assert_equal 2, result["email"]
    assert_equal 1, result["web"]
  end

  test "should exclude tickets with no channel" do
    create_ticket(1, nil)
    create_ticket(2, "email")

    card = Avo::Cards::TicketsByChannel.new
    result = card.query

    assert_equal({"email" => 1}, result)
  end

  private

  def create_ticket(zendesk_id, via)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: "test.zendesk.com",
      subject: "Ticket #{zendesk_id}",
      status: "open",
      via: via
    )
  end
end
