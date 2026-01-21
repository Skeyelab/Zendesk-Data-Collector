require "test_helper"

class DeviseAuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    # Clear Rack::Attack cache before each test to prevent rate limiting
    Rack::Attack.cache.store.clear if Rack::Attack.cache.respond_to?(:store)
  end

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

    # Sign out using DELETE method (Devise requires DELETE for sign out)
    # Use page.driver to submit DELETE request
    page.driver.submit :delete, destroy_admin_user_session_path, {}

    # After sign out, should be redirected (might be root which redirects to sign in)
    # Check that we're no longer authenticated by verifying login page content
    assert_text(/Log in/i)
    # Verify we're not on the avo path anymore
    assert_not_equal avo_path, page.current_path
  end

  test "redirects to login when accessing avo without authentication" do
    visit avo_path

    assert_current_path new_admin_user_session_path
  end
end
