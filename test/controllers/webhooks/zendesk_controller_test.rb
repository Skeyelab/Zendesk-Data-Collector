require "test_helper"
require "webmock/minitest"

class WebhooksZendeskControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Set up webhook secret for tests
    @original_secret = ENV["WEBHOOKS_ZENDESK_SECRET"]
    ENV["WEBHOOKS_ZENDESK_SECRET"] = "test_webhook_secret_123"

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
    ENV["WEBHOOKS_ZENDESK_SECRET"] = @original_secret
  end

  # ========== Tickets Resource Tests ==========

  test "POST with tickets resource and ticket_id (GET) runs proxy inline and returns 200" do
    stub_request(:get, "https://support.example.com/api/v2/tickets/2001.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(
        status: 200,
        body: {ticket: {id: 2001, subject: "Inline get", status: "open"}}.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    payload = {domain: "support.example.com", resource: "tickets", ticket_id: 2001}

    assert_no_difference "ZendeskTicket.count" do
      post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers
    end

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 2001, json["ticket"]["id"]
    assert_equal "Inline get", json["ticket"]["subject"]
  end

  test "POST with tickets resource, method put, ticket_id and body enqueues job and returns 202" do
    payload = {
      domain: "support.example.com",
      resource: "tickets",
      method: "put",
      ticket_id: 2002,
      body: {ticket: {status: "solved"}}
    }

    assert_enqueued_with(job: ZendeskProxyJob,
      args: ["support.example.com", "put", "tickets", 2002,
        {"ticket" => {"status" => "solved"}}]) do
      post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal "accepted", json["status"]
    assert_includes json["message"], "queued"
  end

  test "POST with tickets resource and method post (create) enqueues job without ticket_id" do
    payload = {
      domain: "support.example.com",
      resource: "tickets",
      method: "post",
      body: {ticket: {subject: "New", comment: {body: "Hi"}}}
    }

    assert_enqueued_with(job: ZendeskProxyJob) do
      post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers
    end
    assert_response :accepted
  end

  test "POST with tickets resource, method patch updates ticket and returns 202" do
    payload = {
      domain: "support.example.com",
      resource: "tickets",
      method: "patch",
      ticket_id: 2003,
      body: {ticket: {priority: "high"}}
    }

    assert_enqueued_with(job: ZendeskProxyJob,
      args: ["support.example.com", "patch", "tickets", 2003,
        {"ticket" => {"priority" => "high"}}]) do
      post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers
    end
    assert_response :accepted
  end

  test "POST with tickets resource, method delete executes synchronously and returns result" do
    stub_request(:delete, "https://support.example.com/api/v2/tickets/2004.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(
        status: 204,
        body: "",
        headers: {"Content-Type" => "application/json"}
      )

    payload = {domain: "support.example.com", resource: "tickets", method: "delete", ticket_id: 2004}

    post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers

    assert_response :no_content
  end

  # ========== Users Resource Tests ==========

  test "POST with users resource and user_id (GET) runs proxy inline and returns 200" do
    stub_request(:get, "https://support.example.com/api/v2/users/3001.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(
        status: 200,
        body: {user: {id: 3001, name: "John Doe", email: "john@example.com"}}.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    payload = {domain: "support.example.com", resource: "users", user_id: 3001}

    post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 3001, json["user"]["id"]
    assert_equal "John Doe", json["user"]["name"]
  end

  test "POST with users resource, method post (create) enqueues job without user_id" do
    payload = {
      domain: "support.example.com",
      resource: "users",
      method: "post",
      body: {user: {name: "Jane Doe", email: "jane@example.com", role: "end-user"}}
    }

    assert_enqueued_with(job: ZendeskProxyJob,
      args: ["support.example.com", "post", "users", nil,
        {"user" => {"name" => "Jane Doe", "email" => "jane@example.com", "role" => "end-user"}}]) do
      post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers
    end
    assert_response :accepted
  end

  test "POST with users resource, method put, user_id and body enqueues job and returns 202" do
    payload = {
      domain: "support.example.com",
      resource: "users",
      method: "put",
      user_id: 3002,
      body: {user: {name: "Updated Name"}}
    }

    assert_enqueued_with(job: ZendeskProxyJob,
      args: ["support.example.com", "put", "users", 3002,
        {"user" => {"name" => "Updated Name"}}]) do
      post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers
    end
    assert_response :accepted
  end

  test "POST with users resource, method patch updates user and returns 202" do
    payload = {
      domain: "support.example.com",
      resource: "users",
      method: "patch",
      user_id: 3003,
      body: {user: {role: "agent"}}
    }

    assert_enqueued_with(job: ZendeskProxyJob,
      args: ["support.example.com", "patch", "users", 3003,
        {"user" => {"role" => "agent"}}]) do
      post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers
    end
    assert_response :accepted
  end

  test "POST with users resource, method delete executes synchronously and returns result" do
    stub_request(:delete, "https://support.example.com/api/v2/users/3004.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(
        status: 200,
        body: {user: {id: 3004, active: false}}.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    payload = {domain: "support.example.com", resource: "users", method: "delete", user_id: 3004}

    post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 3004, json["user"]["id"]
  end

  # ========== Validation Tests ==========

  test "POST without domain returns 422" do
    payload = {resource: "tickets", ticket_id: 1003, method: "get"}

    post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "domain is required"
  end

  test "POST without resource returns 422" do
    payload = {domain: "support.example.com", ticket_id: 1003, method: "get"}

    post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "resource is required"
  end

  test "POST with invalid resource returns 422" do
    payload = {domain: "support.example.com", resource: "organizations", method: "get"}

    post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "resource must be one of"
  end

  test "POST with put or post but no body returns 422" do
    post webhooks_zendesk_path,
      params: {domain: "support.example.com", resource: "tickets", method: "put", ticket_id: 1}, as: :json, headers: @valid_headers
    assert_response :unprocessable_entity
    assert_equal "body is required for put/post/patch", JSON.parse(response.body)["error"]

    post webhooks_zendesk_path,
      params: {domain: "support.example.com", resource: "tickets", method: "post"}, as: :json, headers: @valid_headers
    assert_response :unprocessable_entity
    assert_equal "body is required for put/post/patch", JSON.parse(response.body)["error"]

    post webhooks_zendesk_path,
      params: {domain: "support.example.com", resource: "users", method: "patch", user_id: 1}, as: :json, headers: @valid_headers
    assert_response :unprocessable_entity
    assert_equal "body is required for put/post/patch", JSON.parse(response.body)["error"]
  end

  test "POST with tickets resource but invalid body structure returns 422" do
    # Body without 'ticket' key
    post webhooks_zendesk_path,
      params: {domain: "support.example.com", resource: "tickets", method: "post", body: {status: "solved"}}, as: :json, headers: @valid_headers
    assert_response :unprocessable_entity
    assert_equal "body must contain a 'ticket' object", JSON.parse(response.body)["error"]
  end

  test "POST with users resource but invalid body structure returns 422" do
    # Body without 'user' key
    post webhooks_zendesk_path,
      params: {domain: "support.example.com", resource: "users", method: "post", body: {name: "John"}}, as: :json, headers: @valid_headers
    assert_response :unprocessable_entity
    assert_equal "body must contain a 'user' object", JSON.parse(response.body)["error"]
  end

  test "POST with tickets resource but no ticket_id for get/put/patch/delete returns 422" do
    post webhooks_zendesk_path, params: {domain: "support.example.com", resource: "tickets", method: "get"}, as: :json,
      headers: @valid_headers
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "ticket_id is required"

    post webhooks_zendesk_path, params: {domain: "support.example.com", resource: "tickets", method: "put", body: {ticket: {}}}, as: :json,
      headers: @valid_headers
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "ticket_id is required"
  end

  test "POST with users resource but no user_id for get/put/patch/delete returns 422" do
    post webhooks_zendesk_path, params: {domain: "support.example.com", resource: "users", method: "get"}, as: :json,
      headers: @valid_headers
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "user_id is required"

    post webhooks_zendesk_path, params: {domain: "support.example.com", resource: "users", method: "delete"}, as: :json,
      headers: @valid_headers
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "user_id is required"
  end

  test "POST with invalid method returns 422" do
    post webhooks_zendesk_path, params: {domain: "support.example.com", resource: "tickets", ticket_id: 1, method: "options"}, as: :json,
      headers: @valid_headers
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "method must be"
  end

  test "POST with invalid JSON returns 400 or 422" do
    post webhooks_zendesk_path, params: "not json",
      headers: @valid_headers.merge({"Content-Type" => "application/json"})

    assert_includes [400, 422], response.status
  end

  # ========== Authentication Tests ==========

  test "POST without X-Webhook-Secret header returns 401" do
    payload = {domain: "support.example.com", resource: "tickets", ticket_id: 2001}

    post webhooks_zendesk_path, params: payload, as: :json

    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_equal "X-Webhook-Secret header required", json["error"]
  end

  test "POST with invalid X-Webhook-Secret returns 401" do
    payload = {domain: "support.example.com", resource: "tickets", ticket_id: 2001}
    invalid_headers = {"X-Webhook-Secret" => "wrong_secret"}

    post webhooks_zendesk_path, params: payload, as: :json, headers: invalid_headers

    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_equal "Invalid webhook secret", json["error"]
  end

  test "POST falls back to WEBHOOKS_TICKETS_SECRET if WEBHOOKS_ZENDESK_SECRET not set" do
    ENV["WEBHOOKS_ZENDESK_SECRET"] = nil
    ENV["WEBHOOKS_TICKETS_SECRET"] = "legacy_secret"
    headers = {"X-Webhook-Secret" => "legacy_secret"}

    stub_request(:get, "https://support.example.com/api/v2/tickets/2001.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(
        status: 200,
        body: {ticket: {id: 2001}}.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    payload = {domain: "support.example.com", resource: "tickets", ticket_id: 2001}
    post webhooks_zendesk_path, params: payload, as: :json, headers: headers

    assert_response :ok

    ENV["WEBHOOKS_TICKETS_SECRET"] = nil
  end

  # ========== Desk Validation Tests ==========

  test "POST with inactive desk returns 404" do
    @desk.update!(active: false)
    payload = {domain: "support.example.com", resource: "tickets", ticket_id: 2001}

    post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers

    assert_response :not_found
    json = JSON.parse(response.body)
    assert_includes json["error"], "No active desk found"
  end

  test "POST with non-existent domain returns 404" do
    payload = {domain: "nonexistent.zendesk.com", resource: "tickets", ticket_id: 2001}

    post webhooks_zendesk_path, params: payload, as: :json, headers: @valid_headers

    assert_response :not_found
    json = JSON.parse(response.body)
    assert_includes json["error"], "No active desk found"
  end
end
