require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    # Clear Rack::Attack cache before each test
    Rack::Attack.cache.store.clear if Rack::Attack.cache.respond_to?(:store)
  end

  test "throttles excessive login attempts by IP" do
    # Make 5 login attempts (the limit)
    5.times do
      post admin_user_session_path, params: {
        admin_user: { email: "test@example.com", password: "wrong" }
      }
      assert_response :success # Should still allow the requests
    end

    # The 6th attempt should be throttled
    post admin_user_session_path, params: {
      admin_user: { email: "test@example.com", password: "wrong" }
    }
    assert_response :too_many_requests
    assert_match(/Rate limit exceeded/, response.body)
  end

  test "throttles excessive login attempts by email" do
    # Make 5 login attempts with same email (the limit)
    5.times do
      post admin_user_session_path, params: {
        admin_user: { email: "specific@example.com", password: "wrong" }
      }
      assert_response :success # Should still allow the requests
    end

    # The 6th attempt with same email should be throttled
    post admin_user_session_path, params: {
      admin_user: { email: "specific@example.com", password: "wrong" }
    }
    assert_response :too_many_requests
    assert_match(/Rate limit exceeded/, response.body)
  end

  test "does not throttle non-login requests" do
    # Make multiple requests to non-login paths
    10.times do
      get root_path
    end
    # Should not be throttled
    assert_response :redirect # Redirects to login since not authenticated
  end
end
