require "test_helper"

class Avo::Cards::AverageResolutionTimeTest < ActiveSupport::TestCase
  def setup
    # Clean up any existing tickets
    ZendeskTicket.delete_all
  end

  test "should return zero when no tickets exist" do
    card = Avo::Cards::AverageResolutionTime.new
    result = card.query

    assert_equal 0, result
  end

  test "should return zero when no tickets have resolution time" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", full_resolution_time_in_minutes: nil)
    create_zendesk_ticket(zendesk_id: 2, domain: "test.zendesk.com", full_resolution_time_in_minutes: nil)

    card = Avo::Cards::AverageResolutionTime.new
    result = card.query

    assert_equal 0, result
  end

  test "should calculate average resolution time correctly" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", full_resolution_time_in_minutes: 60)  # 1 hour
    create_zendesk_ticket(zendesk_id: 2, domain: "test.zendesk.com", full_resolution_time_in_minutes: 120) # 2 hours

    card = Avo::Cards::AverageResolutionTime.new
    result = card.query

    assert_equal 90, result # Average of 60 and 120
  end

  test "should ignore tickets without resolution time in calculation" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", full_resolution_time_in_minutes: 60)
    create_zendesk_ticket(zendesk_id: 2, domain: "test.zendesk.com", full_resolution_time_in_minutes: nil)
    create_zendesk_ticket(zendesk_id: 3, domain: "test.zendesk.com", full_resolution_time_in_minutes: 180)

    card = Avo::Cards::AverageResolutionTime.new
    result = card.query

    assert_equal 120, result # Average of 60 and 180 (ignores nil)
  end

  test "should handle single ticket with resolution time" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", full_resolution_time_in_minutes: 75)

    card = Avo::Cards::AverageResolutionTime.new
    result = card.query

    assert_equal 75, result
  end

  test "should return integer value" do
    create_zendesk_ticket(zendesk_id: 1, domain: "test.zendesk.com", full_resolution_time_in_minutes: 90)
    create_zendesk_ticket(zendesk_id: 2, domain: "test.zendesk.com", full_resolution_time_in_minutes: 91)

    card = Avo::Cards::AverageResolutionTime.new
    result = card.query

    assert_equal 90, result # Should be integer (90.5 rounded down)
    assert_kind_of Integer, result
  end

  private

  def create_zendesk_ticket(zendesk_id:, domain:, full_resolution_time_in_minutes:)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: domain,
      subject: "Test Ticket #{zendesk_id}",
      status: "solved",
      full_resolution_time_in_minutes: full_resolution_time_in_minutes
    )
  end
end
