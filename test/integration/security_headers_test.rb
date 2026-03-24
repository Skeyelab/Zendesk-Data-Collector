require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "security headers are present in response" do
    get root_path

    # X-Frame-Options prevents clickjacking by restricting iframe embedding
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]

    # X-Content-Type-Options prevents MIME-type sniffing
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]

    # X-XSS-Protection is disabled (0) as modern browsers have deprecated it
    assert_equal "0", response.headers["X-XSS-Protection"]

    # Referrer-Policy controls how much referrer information is sent
    assert_equal "strict-origin-when-cross-origin", response.headers["Referrer-Policy"]

    # Permissions-Policy restricts browser features
    assert_equal "geolocation=(), microphone=(), camera=()", response.headers["Permissions-Policy"]
  end
end
