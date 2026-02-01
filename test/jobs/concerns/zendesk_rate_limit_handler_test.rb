require "test_helper"

# Dummy job to test ZendeskRateLimitHandler concern
class DummyRateLimitJob < ApplicationJob
  include ZendeskRateLimitHandler
end

class ZendeskRateLimitHandlerTest < ActiveJob::TestCase
  def setup
    @desk = Desk.create!(
      domain: "test.zendesk.com",
      user: "test@example.com",
      token: "test_token",
      last_timestamp: 1000,
      active: true,
      queued: false
    )
  end

  test "extracts Retry-After from Faraday exception response_headers" do
    # Faraday::TooManyRequestsError has response_headers method; simulate it
    faraday_error = build_faraday_error_with_retry_after(42)

    job = DummyRateLimitJob.new
    job.send(:handle_rate_limit_error, faraday_error, @desk, 326750, 0, 3)

    @desk.reload
    expected_min = Time.now.to_i + 41  # 42 + 0 retry_count, allow 1s drift
    expected_max = Time.now.to_i + 45
    assert @desk.wait_till >= expected_min, "wait_till #{@desk.wait_till} should be >= #{expected_min} (Retry-After 42)"
    assert @desk.wait_till <= expected_max, "wait_till #{@desk.wait_till} should be <= #{expected_max}"
  end

  test "extracts Retry-After when exception passed directly (response_from_error returns nil)" do
    # When extract_response_from_error returns nil, handle_rate_limit_error receives the exception
    faraday_error = build_faraday_error_with_retry_after(15)

    job = DummyRateLimitJob.new
    job.send(:handle_rate_limit_error, faraday_error, @desk, 999, 1, 3)

    @desk.reload
    # wait_seconds = 15 + 1 (retry_count) = 16
    expected_min = Time.now.to_i + 15
    expected_max = Time.now.to_i + 20
    assert @desk.wait_till >= expected_min, "wait_till should reflect Retry-After 15 + retry 1"
    assert @desk.wait_till <= expected_max, "wait_till should reflect Retry-After 15 + retry 1"
  end

  test "extract_response_status returns status from response object" do
    response = Object.new
    response.define_singleton_method(:status) { 429 }
    job = DummyRateLimitJob.new
    assert_equal 429, job.send(:extract_response_status, response)
  end

  test "extract_response_status returns status from response.env when response has no status method" do
    env = {status: 200}
    response = Object.new
    response.define_singleton_method(:env) { env }
    response.define_singleton_method(:respond_to?) { |m| m == :env || (super(m) if defined?(super)) }
    job = DummyRateLimitJob.new
    assert_equal 200, job.send(:extract_response_status, response)
  end

  test "extract_response_status returns status from Hash (env)" do
    job = DummyRateLimitJob.new
    assert_equal 429, job.send(:extract_response_status, {status: 429})
  end

  test "extract_response_status returns nil for nil or missing status" do
    job = DummyRateLimitJob.new
    assert_nil job.send(:extract_response_status, nil)
    assert_nil job.send(:extract_response_status, {})
  end

  test "parse_response_body returns Hash when body is already a Hash" do
    body = {"tickets" => []}
    response = Object.new
    response.define_singleton_method(:body) { body }
    response.define_singleton_method(:respond_to?) { |m| m == :body || (super(m) if defined?(super)) }
    job = DummyRateLimitJob.new
    assert_equal body, job.send(:parse_response_body, response)
  end

  test "parse_response_body parses JSON string" do
    response = Object.new
    response.define_singleton_method(:body) { '{"key":"value"}' }
    response.define_singleton_method(:respond_to?) { |m| m == :body || (super(m) if defined?(super)) }
    job = DummyRateLimitJob.new
    assert_equal({"key" => "value"}, job.send(:parse_response_body, response))
  end

  test "parse_response_body returns empty Hash for nil response or nil body" do
    job = DummyRateLimitJob.new
    assert_equal({}, job.send(:parse_response_body, nil))
    response = Object.new
    response.define_singleton_method(:body) { nil }
    response.define_singleton_method(:respond_to?) { |m| m == :body || (super(m) if defined?(super)) }
    assert_equal({}, job.send(:parse_response_body, response))
  end

  test "does not log Retry-After header not found when header is present in Faraday exception" do
    faraday_error = build_faraday_error_with_retry_after(42)
    warn_messages = []
    custom_logger = Logger.new($stdout)
    custom_logger.define_singleton_method(:warn) { |msg| warn_messages << msg }

    original_logger = Rails.logger
    Rails.logger = custom_logger
    begin
      job = DummyRateLimitJob.new
      job.send(:handle_rate_limit_error, faraday_error, @desk, 123, 0, 3)
    ensure
      Rails.logger = original_logger
    end

    retry_not_found_warns = warn_messages.select { |m| m.to_s.include?("Retry-After header not found") }
    assert_empty retry_not_found_warns,
      "Should NOT log 'Retry-After header not found' when header is present, but got: #{retry_not_found_warns}"
  end

  private

  def build_faraday_error_with_retry_after(seconds)
    # Simulate Faraday::TooManyRequestsError which has response_headers method
    headers = {"Retry-After" => seconds.to_s}
    error = Object.new
    error.define_singleton_method(:response_headers) { headers }
    error
  end
end
