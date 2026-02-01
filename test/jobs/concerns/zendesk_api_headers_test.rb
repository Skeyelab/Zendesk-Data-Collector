require "test_helper"

class ZendeskApiHeadersTest < ActiveSupport::TestCase
  test "extract_retry_after returns value from env response_headers (ZendeskClientService callback shape)" do
    env = {status: 429, response_headers: {"Retry-After" => "42"}}
    assert_equal 42, ZendeskApiHeaders.extract_retry_after(env)
  end

  test "extract_retry_after returns default when env is nil" do
    assert_equal 10, ZendeskApiHeaders.extract_retry_after(nil)
    assert_equal 15, ZendeskApiHeaders.extract_retry_after(nil, 15)
  end

  test "extract_retry_after returns default when header missing" do
    env = {status: 429, response_headers: {}}
    assert_equal 10, ZendeskApiHeaders.extract_retry_after(env)
  end

  test "extract_retry_after accepts retry-after (lowercase)" do
    env = {response_headers: {"retry-after" => "7"}}
    assert_equal 7, ZendeskApiHeaders.extract_retry_after(env)
  end
end
