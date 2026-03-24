require "test_helper"

class Avo::Cards::OpenTicketsCountTest < ActiveSupport::TestCase
  def setup
    ZendeskTicket.delete_all
  end

  test "should return zero when no tickets exist" do
    card = Avo::Cards::OpenTicketsCount.new
    assert_equal 0, card.query
  end

  test "should count new, open and pending tickets" do
    create_ticket(1, "new")
    create_ticket(2, "open")
    create_ticket(3, "pending")
    create_ticket(4, "solved")
    create_ticket(5, "closed")

    card = Avo::Cards::OpenTicketsCount.new
    assert_equal 3, card.query
  end

  test "should not count solved or closed tickets" do
    create_ticket(1, "solved")
    create_ticket(2, "closed")

    card = Avo::Cards::OpenTicketsCount.new
    assert_equal 0, card.query
  end

  private

  def create_ticket(zendesk_id, status)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: "test.zendesk.com",
      subject: "Ticket #{zendesk_id}",
      status: status
    )
  end
end
