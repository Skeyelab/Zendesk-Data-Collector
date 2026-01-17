require "application_system_test_case"

class AvoTest < ApplicationSystemTestCase
  def setup
    @admin_user = AdminUser.create!(
      email: "admin@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "visiting the avo index" do
    visit new_admin_user_session_path
    fill_in "Email", with: @admin_user.email
    fill_in "Password", with: "password123"
    click_button "Log in"

    visit avo_path

    assert_selector "h1", text: "Zendesk Data Collector"
  end

  test "can view desks list" do
    desk = Desk.create!(
      domain: "test.zendesk.com",
      user: "test@example.com",
      token: "test_token",
      active: true
    )

    visit new_admin_user_session_path
    fill_in "Email", with: @admin_user.email
    fill_in "Password", with: "password123"
    click_button "Log in"

    visit avo.resources_desks_path

    assert_text desk.domain
    assert_text desk.user
  end

  test "can create a new desk" do
    visit new_admin_user_session_path
    fill_in "Email", with: @admin_user.email
    fill_in "Password", with: "password123"
    click_button "Log in"

    visit avo.resources_desks_path
    click_on "New desk"

    fill_in "Domain", with: "newtest.zendesk.com"
    fill_in "User", with: "newuser@example.com"
    fill_in "Token", with: "new_token_123"
    check "Active"

    click_on "Save"

    assert_text "Desk was successfully created"
    assert_text "newtest.zendesk.com"
  end

  test "can edit a desk" do
    desk = Desk.create!(
      domain: "test.zendesk.com",
      user: "test@example.com",
      token: "test_token",
      active: false
    )

    visit new_admin_user_session_path
    fill_in "Email", with: @admin_user.email
    fill_in "Password", with: "password123"
    click_button "Log in"

    visit avo.resources_desk_path(desk)

    click_on "Edit"
    check "Active"
    click_on "Save"

    assert_text "Desk was successfully updated"
    desk.reload
    assert desk.active
  end

  test "can view admin users" do
    visit new_admin_user_session_path
    fill_in "Email", with: @admin_user.email
    fill_in "Password", with: "password123"
    click_button "Log in"

    visit avo.resources_admin_users_path

    assert_text @admin_user.email
  end
end
