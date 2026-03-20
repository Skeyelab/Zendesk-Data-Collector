require "test_helper"

class DeviseAuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    # Clear Rack::Attack cache before each test to prevent rate limiting
    Rack::Attack.cache&.store&.clear
  end

  test "can sign in with valid credentials" do
    admin_user = AdminUser.create!(
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    visit new_admin_user_session_path
    fill_in "Email", with: admin_user.email
    fill_in "Password", with: "password123"
    click_button "Log in"

    assert_text(/Signed in successfully/i)
  end

  test "cannot sign in with invalid credentials" do
    visit new_admin_user_session_path
    fill_in "Email", with: "wrong@example.com"
    fill_in "Password", with: "wrongpassword"
    click_button "Log in"

    assert_current_path new_admin_user_session_path
    assert_text(/Log in/i)
  end

  test "can sign out" do
    admin_user = AdminUser.create!(
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    # Use integration session only here — mixing Capybara `visit` with `delete` uses a
    # separate cookie jar, so sign-out would not apply to subsequent `visit` calls.
    sign_in admin_user, scope: :admin_user
    get avo_path
    assert_response :redirect
    assert_match(%r{/avo/}, response.headers["Location"].to_s)

    # Path helpers are scoped to the last engine request (/avo); Devise lives on the main app.
    delete "/admin_users/sign_out"
    assert_response :redirect
    follow_redirect!

    get avo_path
    # Either no route (404) or Devise sends guests to sign in (302), depending on routing stack.
    assert_includes [302, 404], response.status
    if response.redirect?
      assert_match(%r{/admin_users/sign_in}, response.headers["Location"].to_s)
    end
  end

  test "redirects to login when accessing avo without authentication" do
    visit avo_path

    assert_current_path new_admin_user_session_path
  end
end
