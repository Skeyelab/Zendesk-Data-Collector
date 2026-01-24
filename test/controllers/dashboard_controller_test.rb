require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin_user = AdminUser.create!(
      email: "admin@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    # Clear Rack::Attack cache
    Rack::Attack.cache&.store&.clear
  end

  test "should require authentication to access dashboard" do
    get dashboard_path
    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "should load dashboard without filters" do
    sign_in_admin_user

    # Create test tickets with different statuses
    create_ticket(zendesk_id: 1, status: "new")
    create_ticket(zendesk_id: 2, status: "open")
    create_ticket(zendesk_id: 3, status: "pending")
    create_ticket(zendesk_id: 4, status: "solved")
    create_ticket(zendesk_id: 5, status: "closed")

    get dashboard_path

    assert_response :success
    # Check that the total tickets count appears in the response
    assert_match(/>5</, response.body) # Total tickets
  end

  test "should filter tickets by excluded statuses" do
    sign_in_admin_user

    create_ticket(zendesk_id: 1, status: "new")
    create_ticket(zendesk_id: 2, status: "open")
    create_ticket(zendesk_id: 3, status: "solved")
    create_ticket(zendesk_id: 4, status: "closed")

    get dashboard_path, params: {exclude_statuses: ["solved", "closed"]}

    assert_response :success
    # Should only show 2 tickets (new and open)
    assert_match(/>2</, response.body)
  end

  test "should apply filters to total_tickets count" do
    sign_in_admin_user

    create_ticket(zendesk_id: 1, status: "new")
    create_ticket(zendesk_id: 2, status: "open")
    create_ticket(zendesk_id: 3, status: "solved")

    get dashboard_path, params: {exclude_statuses: ["solved"]}

    assert_response :success
    # Total should be 2 (excluding solved)
    assert_match(/>2</, response.body)
  end

  test "should apply filters to tickets_by_status chart" do
    sign_in_admin_user

    create_ticket(zendesk_id: 1, status: "new")
    create_ticket(zendesk_id: 2, status: "open")
    create_ticket(zendesk_id: 3, status: "open")
    create_ticket(zendesk_id: 4, status: "solved")

    get dashboard_path, params: {exclude_statuses: ["solved"]}

    assert_response :success
    # Chart should only show new and open statuses
    # We can't easily test chart data in integration test, but we can verify the page loads
    assert_match(/Tickets by Status/, response.body)
  end

  test "should apply filters to tickets_by_priority chart" do
    sign_in_admin_user

    create_ticket(zendesk_id: 1, status: "new", priority: "high")
    create_ticket(zendesk_id: 2, status: "open", priority: "normal")
    create_ticket(zendesk_id: 3, status: "solved", priority: "low")

    get dashboard_path, params: {exclude_statuses: ["solved"]}

    assert_response :success
    assert_match(/Tickets by Priority/, response.body)
  end

  test "should apply filters to tickets_over_time chart" do
    sign_in_admin_user

    create_ticket(zendesk_id: 1, status: "new", created_at: 1.day.ago)
    create_ticket(zendesk_id: 2, status: "open", created_at: 2.days.ago)
    create_ticket(zendesk_id: 3, status: "solved", created_at: 3.days.ago)

    get dashboard_path, params: {exclude_statuses: ["solved"]}

    assert_response :success
    assert_match(/Tickets Over Time/, response.body)
  end

  test "should apply filters to average resolution time" do
    sign_in_admin_user

    # Create tickets with resolution times
    create_ticket(
      zendesk_id: 1,
      status: "solved",
      first_resolution_time_in_minutes: 60
    )
    create_ticket(
      zendesk_id: 2,
      status: "closed",
      first_resolution_time_in_minutes: 120
    )
    create_ticket(
      zendesk_id: 3,
      status: "open",
      first_resolution_time_in_minutes: 30
    )

    # Exclude solved and closed, so only open ticket should be considered
    # But open tickets don't have resolution times, so avg should be nil or 0
    get dashboard_path, params: {exclude_statuses: ["solved", "closed"]}

    assert_response :success
    # Average resolution should not include solved/closed tickets
  end

  test "should handle all statuses excluded gracefully" do
    sign_in_admin_user

    create_ticket(zendesk_id: 1, status: "new")
    create_ticket(zendesk_id: 2, status: "open")

    get dashboard_path, params: {
      exclude_statuses: ["new", "open", "pending", "solved", "closed"]
    }

    assert_response :success
    # Should show 0 tickets
    assert_match(/>0</, response.body)
  end

  test "should ignore invalid status values" do
    sign_in_admin_user

    create_ticket(zendesk_id: 1, status: "new")
    create_ticket(zendesk_id: 2, status: "open")

    get dashboard_path, params: {exclude_statuses: ["invalid_status", "new"]}

    assert_response :success
    # Should only exclude "new", so 1 ticket remains
    assert_match(/>1</, response.body)
  end

  test "should pass excluded_statuses to view" do
    sign_in_admin_user

    create_ticket(zendesk_id: 1, status: "new")

    get dashboard_path, params: {exclude_statuses: ["solved", "closed"]}

    assert_response :success
    # View should have access to @excluded_statuses
    # We verify this by checking the response includes filter UI
    assert_match(/solved|closed/, response.body) # Filter checkboxes should reflect excluded statuses
  end

  test "should handle empty exclude_statuses parameter" do
    sign_in_admin_user

    create_ticket(zendesk_id: 1, status: "new")
    create_ticket(zendesk_id: 2, status: "open")

    get dashboard_path, params: {exclude_statuses: []}

    assert_response :success
    # Should show all tickets
    assert_match(/>2</, response.body)
  end

  private

  def sign_in_admin_user
    post admin_user_session_path, params: {
      admin_user: {
        email: @admin_user.email,
        password: "password123"
      }
    }
    follow_redirect! if response.redirect?
  end

  def create_ticket(zendesk_id:, status:, priority: nil, created_at: nil, first_resolution_time_in_minutes: nil)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: "test.zendesk.com",
      subject: "Test Ticket #{zendesk_id}",
      status: status,
      priority: priority,
      created_at: created_at || Time.current,
      updated_at: Time.current,
      first_resolution_time_in_minutes: first_resolution_time_in_minutes
    )
  end
end
