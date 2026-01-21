require "test_helper"

class MissionControl::BaseControllerTest < ActionDispatch::IntegrationTest
  test "should require authentication to access Mission Control" do
    get "/jobs"
    # Devise redirects to sign in path - check redirect status and path
    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "should allow access when authenticated" do
    admin_user = AdminUser.create!(
      email: "admin@example.com",
      password: "password123456",
      password_confirmation: "password123456"
    )

    # Sign in using Devise test helper with the correct scope
    sign_in admin_user, scope: :admin_user

    get "/jobs"
    assert_response :success
  end
end
