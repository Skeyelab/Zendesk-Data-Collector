require "test_helper"

class Avo::Cards::TicketsByAssigneeTest < ActiveSupport::TestCase
  def setup
    ZendeskTicket.delete_all
  end

  test "should return empty hash when no tickets exist" do
    card = Avo::Cards::TicketsByAssignee.new
    assert_equal({}, card.query)
  end

  test "should group tickets by assignee name" do
    create_ticket(1, "Alice")
    create_ticket(2, "Alice")
    create_ticket(3, "Bob")

    card = Avo::Cards::TicketsByAssignee.new
    result = card.query

    assert_equal 2, result["Alice"]
    assert_equal 1, result["Bob"]
  end

  test "should exclude tickets with no assignee" do
    create_ticket(1, nil)
    create_ticket(2, "Alice")

    card = Avo::Cards::TicketsByAssignee.new
    result = card.query

    assert_equal({"Alice" => 1}, result)
  end

  test "should limit results to top 10 assignees" do
    12.times { |i| create_ticket(i + 1, "Agent #{i + 1}") }

    card = Avo::Cards::TicketsByAssignee.new
    assert_operator card.query.size, :<=, 10
  end

  test "should sort by count descending" do
    create_ticket(1, "Bob")
    create_ticket(2, "Alice")
    create_ticket(3, "Alice")

    card = Avo::Cards::TicketsByAssignee.new
    result = card.query

    assert_equal "Alice", result.keys.first
  end

  private

  def create_ticket(zendesk_id, assignee_name)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: "test.zendesk.com",
      subject: "Ticket #{zendesk_id}",
      status: "open",
      assignee_name: assignee_name
    )
  end
end
