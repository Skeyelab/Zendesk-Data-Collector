require "test_helper"

class Avo::Cards::FirstReplyTimeTest < ActiveSupport::TestCase
  def setup
    ZendeskTicket.delete_all
  end

  test "should return zero when no tickets exist" do
    card = Avo::Cards::FirstReplyTime.new
    assert_equal 0, card.query
  end

  test "should return zero when no tickets have first reply time" do
    create_ticket(1, nil)
    card = Avo::Cards::FirstReplyTime.new
    assert_equal 0, card.query
  end

  test "should calculate average first reply time" do
    create_ticket(1, 60)
    create_ticket(2, 120)

    card = Avo::Cards::FirstReplyTime.new
    assert_equal 90, card.query
  end

  test "should ignore tickets without first reply time" do
    create_ticket(1, 60)
    create_ticket(2, nil)
    create_ticket(3, 180)

    card = Avo::Cards::FirstReplyTime.new
    assert_equal 120, card.query
  end

  test "should return an integer" do
    create_ticket(1, 91)
    create_ticket(2, 90)

    card = Avo::Cards::FirstReplyTime.new
    result = card.query
    assert_kind_of Integer, result
    assert_equal 90, result
  end

  private

  def create_ticket(zendesk_id, first_reply_time)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: "test.zendesk.com",
      subject: "Ticket #{zendesk_id}",
      status: "open",
      first_reply_time_in_minutes: first_reply_time
    )
  end
end
