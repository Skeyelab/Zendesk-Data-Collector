require 'test_helper'

class MissionControl::BaseControllerTest < ActionDispatch::IntegrationTest
  test "should require authentication to access Mission Control" do
    get '/jobs'
    # Devise redirects to sign in path - check redirect status and path
    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "should allow access when authenticated" do
    admin_user = AdminUser.create!(
      email: 'admin@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )

    post admin_user_session_path, params: {
      admin_user: {
        email: admin_user.email,
        password: 'password123'
      }
    }
    follow_redirect! if response.redirect?

    get '/jobs'
    assert_response :success
  end
end
