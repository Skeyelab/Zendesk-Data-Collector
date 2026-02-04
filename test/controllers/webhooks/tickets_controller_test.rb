require "test_helper"
require "webmock/minitest"

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

  test "POST with domain and ticket_id (GET) runs proxy inline and returns 200 with ticket body" do
    stub_request(:get, "https://support.example.com/api/v2/tickets/2001.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(
        status: 200,
        body: {ticket: {id: 2001, subject: "Inline get", status: "open"}}.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    payload = {domain: "support.example.com", ticket_id: 2001}

    assert_no_difference "ZendeskTicket.count" do
      post webhooks_tickets_path, params: payload, as: :json, headers: @valid_headers
    end

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 2001, json["ticket"]["id"]
    assert_equal "Inline get", json["ticket"]["subject"]
  end

  test "POST with domain, method put, ticket_id and body enqueues ZendeskProxyJob and returns 202" do
    payload = {
      domain: "support.example.com",
      method: "put",
      ticket_id: 2002,
      body: {ticket: {status: "solved"}}
    }

    assert_enqueued_with(job: ZendeskProxyJob,
      args: ["support.example.com", "put", 2002,
        {"ticket" => {"status" => "solved"}}]) do
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

  test "POST with put or post but no body returns 422" do
    post webhooks_tickets_path,
      params: {domain: "support.example.com", method: "put", ticket_id: 1}, as: :json, headers: @valid_headers
    assert_response :unprocessable_entity
    assert_equal "body is required for put/post", JSON.parse(response.body)["error"]

    post webhooks_tickets_path,
      params: {domain: "support.example.com", method: "post"}, as: :json, headers: @valid_headers
    assert_response :unprocessable_entity
    assert_equal "body is required for put/post", JSON.parse(response.body)["error"]
  end

  test "POST with get/put but no ticket_id returns 422" do
    post webhooks_tickets_path, params: {domain: "support.example.com", method: "get"}, as: :json,
      headers: @valid_headers
    assert_response :unprocessable_entity

    post webhooks_tickets_path, params: {domain: "support.example.com", method: "put", body: {ticket: {}}}, as: :json,
      headers: @valid_headers
    assert_response :unprocessable_entity
  end

  test "POST with invalid method returns 422" do
    post webhooks_tickets_path, params: {domain: "support.example.com", ticket_id: 1, method: "delete"}, as: :json,
      headers: @valid_headers
    assert_response :unprocessable_entity
  end

  test "POST with invalid JSON returns 400 or 422" do
    post webhooks_tickets_path, params: "not json",
      headers: @valid_headers.merge({"Content-Type" => "application/json"})

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
