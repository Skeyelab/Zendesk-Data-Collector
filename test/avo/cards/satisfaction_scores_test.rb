require "test_helper"

class Avo::Cards::SatisfactionScoresTest < ActiveSupport::TestCase
  def setup
    ZendeskTicket.delete_all
  end

  test "should return empty hash when no tickets exist" do
    card = Avo::Cards::SatisfactionScores.new
    assert_equal({}, card.query)
  end

  test "should group tickets by satisfaction score" do
    create_ticket(1, "good")
    create_ticket(2, "good")
    create_ticket(3, "bad")

    card = Avo::Cards::SatisfactionScores.new
    result = card.query

    assert_equal 2, result["good"]
    assert_equal 1, result["bad"]
  end

  test "should exclude tickets with no satisfaction score" do
    create_ticket(1, nil)
    create_ticket(2, "good")

    card = Avo::Cards::SatisfactionScores.new
    result = card.query

    assert_equal({"good" => 1}, result)
  end

  test "should exclude unoffered satisfaction scores" do
    create_ticket(1, "unoffered")
    create_ticket(2, "good")

    card = Avo::Cards::SatisfactionScores.new
    result = card.query

    assert_equal({"good" => 1}, result)
    assert_nil result["unoffered"]
  end

  private

  def create_ticket(zendesk_id, satisfaction_score)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: "test.zendesk.com",
      subject: "Ticket #{zendesk_id}",
      status: "solved",
      satisfaction_score: satisfaction_score
    )
  end
end
