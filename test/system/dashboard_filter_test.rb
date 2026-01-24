require "test_helper"

class DashboardFilterTest < ApplicationSystemTestCase
  def setup
    @admin_user = AdminUser.create!(
      email: "admin@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    # Create test tickets with different statuses
    create_ticket(zendesk_id: 1, status: "new")
    create_ticket(zendesk_id: 2, status: "open")
    create_ticket(zendesk_id: 3, status: "pending")
    create_ticket(zendesk_id: 4, status: "solved")
    create_ticket(zendesk_id: 5, status: "closed")
  end

  test "filter UI is visible on dashboard" do
    sign_in_user

    visit dashboard_path

    assert_text "Filter by Status"
    # Check that all status checkboxes are present
    assert_selector "input[type='checkbox'][value='new']"
    assert_selector "input[type='checkbox'][value='open']"
    assert_selector "input[type='checkbox'][value='pending']"
    assert_selector "input[type='checkbox'][value='solved']"
    assert_selector "input[type='checkbox'][value='closed']"
  end

  test "checking status updates URL and filters metrics" do
    sign_in_user

    visit dashboard_path

    # Initially should show all 5 tickets
    assert_text "5", count: 1 # Total tickets metric

    # Check "solved" and "closed" to exclude them
    check "filter_solved"
    check "filter_closed"

    # Wait for URL to update and page to reload/update
    # The JavaScript triggers a page reload, so wait for it
    sleep 1
    assert_current_path(/exclude_statuses/)
    assert_match(/exclude_statuses/, current_url)

    # Should now show 3 tickets (excluding solved and closed)
    # Wait a bit for the page to fully load after redirect
    assert_text "3" # Total tickets metric
  end

  test "unchecking status removes filter" do
    sign_in_user

    # Visit with filters already applied
    visit dashboard_path(exclude_statuses: ["solved", "closed"])

    # Should show 3 tickets
    assert_text "3", count: 1

    # Uncheck "solved"
    uncheck "filter_solved"
    
    # Wait for page reload
    sleep 1

    # Should now show 4 tickets (only closed excluded)
    assert_text "4"
  end

  test "page reload with URL parameters maintains filter state" do
    sign_in_user

    # Visit with filters in URL
    visit dashboard_path(exclude_statuses: ["solved", "closed"])

    # Checkboxes should be checked - use find by ID
    assert find("#filter_solved").checked?
    assert find("#filter_closed").checked?
    assert_not find("#filter_new").checked?
    assert_not find("#filter_open").checked?
    assert_not find("#filter_pending").checked?

    # Metrics should reflect filters
    assert_text "3", count: 1 # Total tickets
  end

  test "filter checkboxes reflect current URL parameters" do
    sign_in_user

    visit dashboard_path(exclude_statuses: ["new", "open"])

    assert find("#filter_new").checked?
    assert find("#filter_open").checked?
    assert_not find("#filter_pending").checked?
    assert_not find("#filter_solved").checked?
    assert_not find("#filter_closed").checked?
  end

  test "charts update when filters change" do
    sign_in_user

    visit dashboard_path

    # Check that charts are present
    assert_text "Tickets by Status"
    assert_text "Tickets by Priority"
    assert_text "Tickets Over Time"

    # Apply filter
    check "filter_solved"
    check "filter_closed"
    
    # Wait for page reload
    sleep 1

    # Charts should still be present (they update via JavaScript or page reload)
    assert_text "Tickets by Status"
  end

  private

  def sign_in_user
    visit new_admin_user_session_path
    fill_in "Email", with: @admin_user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    # Wait for redirect after login
    assert_text(/Signed in successfully|Zendesk Metrics/i)
  end

  def create_ticket(zendesk_id:, status:)
    ZendeskTicket.create!(
      zendesk_id: zendesk_id,
      domain: "test.zendesk.com",
      subject: "Test Ticket #{zendesk_id}",
      status: status,
      created_at: Time.current,
      updated_at: Time.current
    )
  end
end
