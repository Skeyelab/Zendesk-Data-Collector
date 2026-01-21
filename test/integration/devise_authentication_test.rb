require "test_helper"

class DeviseAuthenticationTest < ActionDispatch::IntegrationTest
  test "can sign in with valid credentials" do
    admin_user = AdminUser.create!(
      email: "test@example.com",
      password: "password123456",
      password_confirmation: "password123456"
    )

    visit new_admin_user_session_path
    fill_in "Email", with: admin_user.email
    fill_in "Password", with: "password123456"
    click_button "Log in"

    assert_text(/Signed in successfully/i)
  end

  test "cannot sign in with invalid credentials" do
    visit new_admin_user_session_path
    fill_in "Email", with: "wrong@example.com"
    fill_in "Password", with: "wrongpassword123"
    click_button "Log in"

    assert_current_path new_admin_user_session_path
    assert_text(/Log in/i)
  end

  test "can sign out" do
    admin_user = AdminUser.create!(
      email: "test@example.com",
      password: "password123456",
      password_confirmation: "password123456"
    )

    visit new_admin_user_session_path
    fill_in "Email", with: admin_user.email
    fill_in "Password", with: "password123456"
    click_button "Log in"

    visit avo_path

    click_on "Sign out", match: :first

    assert_current_path new_admin_user_session_path
    assert_text(/Log in/i)
  end

  test "redirects to login when accessing avo without authentication" do
    visit avo_path

    assert_current_path new_admin_user_session_path
  end
end
