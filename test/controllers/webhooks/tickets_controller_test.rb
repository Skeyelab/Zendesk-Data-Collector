require "test_helper"

class WebhooksTicketsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Set up webhook secret for tests
    @original_secret = ENV["WEBHOOKS_TICKETS_SECRET"]
    ENV["WEBHOOKS_TICKETS_SECRET"] = "test_webhook_secret_123"

    @desk = Desk.create!(
      domain: "support.example.com",
      user: "user@example.com",
      token: "token",
      active: true,
      queued: false
    )

    @valid_headers = {
      "X-Webhook-Secret" => "test_webhook_secret_123"
    }
  end

  teardown do
    ENV["WEBHOOKS_TICKETS_SECRET"] = @original_secret
  end

  test "POST with domain and ticket_id enqueues ZendeskProxyJob (default get) and returns 202" do
    payload = {domain: "support.example.com", ticket_id: 2001}

    # Ensure we never create ZendeskTicket rows when proxying the request
    assert_no_difference "ZendeskTicket.count" do
      assert_enqueued_with(job: ZendeskProxyJob, args: ["support.example.com", "get", 2001, nil]) do
        post webhooks_tickets_path, params: payload, as: :json, headers: @valid_headers
      end
    end

    assert_response :accepted
  end

  test "POST with domain, method put, ticket_id and body enqueues ZendeskProxyJob and returns 202" do
    payload = {
      domain: "support.example.com",
      method: "put",
      ticket_id: 2002,
      body: {ticket: {status: "solved"}}
    }

    assert_enqueued_with(job: ZendeskProxyJob, args: ["support.example.com", "put", 2002, {"ticket" => {"status" => "solved"}}]) do
      post webhooks_tickets_path, params: payload, as: :json, headers: @valid_headers
    end

    assert_response :accepted
  end

  test "POST with domain and method post (create) enqueues ZendeskProxyJob without ticket_id" do
    payload = {
      domain: "support.example.com",
      method: "post",
      body: {ticket: {subject: "New", comment: {body: "Hi"}}}
    }

    assert_enqueued_with(job: ZendeskProxyJob) do
      post webhooks_tickets_path, params: payload, as: :json, headers: @valid_headers
    end
    assert_response :accepted
  end

  test "POST without domain returns 422" do
    payload = {ticket_id: 1003, method: "get"}

    post webhooks_tickets_path, params: payload, as: :json, headers: @valid_headers

    assert_response :unprocessable_entity
  end

  test "POST with get/put but no ticket_id returns 422" do
    post webhooks_tickets_path, params: {domain: "support.example.com", method: "get"}, as: :json, headers: @valid_headers
    assert_response :unprocessable_entity

    post webhooks_tickets_path, params: {domain: "support.example.com", method: "put"}, as: :json, headers: @valid_headers
    assert_response :unprocessable_entity
  end

  test "POST with invalid method returns 422" do
    post webhooks_tickets_path, params: {domain: "support.example.com", ticket_id: 1, method: "delete"}, as: :json, headers: @valid_headers
    assert_response :unprocessable_entity
  end

  test "POST with invalid JSON returns 400 or 422" do
    post webhooks_tickets_path, params: "not json", headers: @valid_headers.merge({"Content-Type" => "application/json"})

    assert_includes [400, 422], response.status
  end

  test "POST without X-Webhook-Secret header returns 401" do
    payload = {domain: "support.example.com", ticket_id: 2001}

    post webhooks_tickets_path, params: payload, as: :json

    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_equal "X-Webhook-Secret header required", json["error"]
  end

  test "POST with invalid X-Webhook-Secret returns 401" do
    payload = {domain: "support.example.com", ticket_id: 2001}
    invalid_headers = {"X-Webhook-Secret" => "wrong_secret"}

    post webhooks_tickets_path, params: payload, as: :json, headers: invalid_headers

    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_equal "Invalid webhook secret", json["error"]
  end

  test "POST with inactive desk returns 404" do
    @desk.update!(active: false)
    payload = {domain: "support.example.com", ticket_id: 2001}

    post webhooks_tickets_path, params: payload, as: :json, headers: @valid_headers

    assert_response :not_found
    json = JSON.parse(response.body)
    assert_includes json["error"], "No active desk found"
  end

  test "POST with non-existent domain returns 404" do
    payload = {domain: "nonexistent.zendesk.com", ticket_id: 2001}

    post webhooks_tickets_path, params: payload, as: :json, headers: @valid_headers

    assert_response :not_found
    json = JSON.parse(response.body)
    assert_includes json["error"], "No active desk found"
  end
end
