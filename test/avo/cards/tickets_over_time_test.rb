require "test_helper"

class Avo::Cards::TicketsOverTimeTest < ActiveSupport::TestCase
  def setup
    # Clean up any existing tickets
    ZendeskTicket.delete_all
  end

  test "should return empty hash when no tickets exist" do
    card = Avo::Cards::TicketsOverTime.new
    result = card.query

    assert_equal({}, result)
  end

  test "should group tickets by date correctly" do
    today = Date.current
    yesterday = today - 1.day
    two_days_ago = today - 2.days

    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", created_at: two_days_ago.to_time)
    create_zendesk_ticket(zendesk_id: 2, domain: "test.zendesk.com", created_at: yesterday.to_time)
    create_zendesk_ticket(zendesk_id: 3, domain: "test.zendesk.com", created_at: yesterday.to_time)
    create_zendesk_ticket(zendesk_id: 4, domain: "test.zendesk.com", created_at: today.to_time)

    card = Avo::Cards::TicketsOverTime.new
    result = card.query

    expected = {
      two_days_ago.strftime("%Y-%m-%d") => 1,
      yesterday.strftime("%Y-%m-%d") => 2,
      today.strftime("%Y-%m-%d") => 1
    }
    assert_equal expected, result
  end

  test "should use date format for grouping" do
    specific_date = Date.new(2024, 1, 15)

    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", created_at: specific_date.to_time)

    card = Avo::Cards::TicketsOverTime.new
    result = card.query

    assert_equal ["2024-01-15"], result.keys
    assert_equal 1, result["2024-01-15"]
  end

  test "should count tickets from all domains together" do
    today = Date.current

    create_zendesk_ticket(zendesk_id: 1, domain: "domain1.zendesk.com", created_at: today.to_time)
    create_zendesk_ticket(zendesk_id: 2, domain: "domain2.zendesk.com", created_at: today.to_time)

    card = Avo::Cards::TicketsOverTime.new
    result = card.query

    expected = {
      today.strftime("%Y-%m-%d") => 2
    }
    assert_equal expected, result
  end

  test "should handle tickets created at different times on same date" do
    date = Date.current

    # Different times on same date
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", created_at: date.to_time.beginning_of_day)
    create_zendesk_ticket(zendesk_id: 2, domain: "test.zendesk.com", created_at: date.to_time.end_of_day)

    card = Avo::Cards::TicketsOverTime.new
    result = card.query

    expected = {
      date.strftime("%Y-%m-%d") => 2
    }
    assert_equal expected, result
  end

  test "should return hash with string keys and integer values" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", created_at: Time.current)

    card = Avo::Cards::TicketsOverTime.new
    result = card.query

    assert_kind_of Hash, result
    assert_kind_of String, result.keys.first
    assert_kind_of Integer, result.values.first
  end

  private

  def create_zendesk_ticket(zendesk_id:, domain:, created_at:)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: domain,
      subject: "Test Ticket #{zendesk_id}",
      status: "open",
      created_at: created_at
    )
  end
end
