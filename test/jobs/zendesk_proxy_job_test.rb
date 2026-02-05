require "test_helper"
require "webmock/minitest"

class ZendeskProxyJobTest < ActiveJob::TestCase
  def setup
    @desk = Desk.create!(
      domain: "support.example.com",
      user: "user@example.com",
      token: "token",
      active: true,
      queued: false,
      wait_till: 0
    )
  end

  def stub_ticket_get(ticket_id, ticket_data, status: 200)
    stub_request(:get, "https://support.example.com/api/v2/tickets/#{ticket_id}.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(
        status: status,
        body: {ticket: ticket_data}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
  end

  def stub_ticket_put(ticket_id, status: 200)
    stub_request(:put, "https://support.example.com/api/v2/tickets/#{ticket_id}.json")
      .with(
        basic_auth: ["user@example.com/token", "token"],
        body: {ticket: {status: "solved"}}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
      .to_return(status: status, body: {ticket: {id: ticket_id}}.to_json, headers: {"Content-Type" => "application/json"})
  end

  def stub_user_get(user_id, user_data, status: 200)
    stub_request(:get, "https://support.example.com/api/v2/users/#{user_id}.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(
        status: status,
        body: {user: user_data}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
  end

  # ========== Tickets Resource Tests ==========

  test "GET ticket proxies to Zendesk, returns status and body, and does not create ZendeskTicket" do
    stub_ticket_get(3001, {id: 3001, subject: "Proxy get", status: "open"})

    assert_no_difference "ZendeskTicket.count" do
      result = ZendeskProxyJob.perform_now("support.example.com", "get", "tickets", 3001, nil)
      assert_equal 200, result[0]
      assert_equal 3001, result[1]["ticket"]["id"]
      assert_equal "Proxy get", result[1]["ticket"]["subject"]
    end
  end

  test "PUT ticket proxies to Zendesk and does not create ZendeskTicket" do
    stub_ticket_put(3002)

    assert_no_difference "ZendeskTicket.count" do
      ZendeskProxyJob.perform_now("support.example.com", "put", "tickets", 3002, {"ticket" => {"status" => "solved"}})
    end
  end

  test "PATCH ticket proxies to Zendesk and does not create ZendeskTicket" do
    stub_request(:patch, "https://support.example.com/api/v2/tickets/3005.json")
      .with(
        basic_auth: ["user@example.com/token", "token"],
        body: {ticket: {priority: "high"}}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
      .to_return(status: 200, body: {ticket: {id: 3005, priority: "high"}}.to_json, headers: {"Content-Type" => "application/json"})

    assert_no_difference "ZendeskTicket.count" do
      ZendeskProxyJob.perform_now("support.example.com", "patch", "tickets", 3005, {"ticket" => {"priority" => "high"}})
    end
  end

  test "DELETE ticket proxies to Zendesk and returns status" do
    stub_request(:delete, "https://support.example.com/api/v2/tickets/3006.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(status: 204, body: "", headers: {"Content-Type" => "application/json"})

    assert_no_difference "ZendeskTicket.count" do
      result = ZendeskProxyJob.perform_now("support.example.com", "delete", "tickets", 3006, nil)
      assert_equal 204, result[0]
      # DELETE typically returns empty body with 204 status
      assert result[1].empty? || result[1].is_a?(Hash)
    end
  end

  test "POST ticket creates new ticket" do
    stub_request(:post, "https://support.example.com/api/v2/tickets.json")
      .with(
        basic_auth: ["user@example.com/token", "token"],
        body: {ticket: {subject: "New ticket", comment: {body: "Test"}}}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
      .to_return(status: 201, body: {ticket: {id: 9999, subject: "New ticket"}}.to_json, headers: {"Content-Type" => "application/json"})

    assert_no_difference "ZendeskTicket.count" do
      ZendeskProxyJob.perform_now("support.example.com", "post", "tickets", nil, {"ticket" => {"subject" => "New ticket", "comment" => {"body" => "Test"}}})
    end
  end

  # ========== Users Resource Tests ==========

  test "GET user proxies to Zendesk and returns user data" do
    stub_user_get(4001, {id: 4001, name: "John Doe", email: "john@example.com"})

    result = ZendeskProxyJob.perform_now("support.example.com", "get", "users", 4001, nil)
    assert_equal 200, result[0]
    assert_equal 4001, result[1]["user"]["id"]
    assert_equal "John Doe", result[1]["user"]["name"]
  end

  test "POST user creates new user" do
    stub_request(:post, "https://support.example.com/api/v2/users.json")
      .with(
        basic_auth: ["user@example.com/token", "token"],
        body: {user: {name: "Jane Doe", email: "jane@example.com"}}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
      .to_return(status: 201, body: {user: {id: 4002, name: "Jane Doe"}}.to_json, headers: {"Content-Type" => "application/json"})

    # POST is async, so it doesn't return a result
    assert_nothing_raised do
      ZendeskProxyJob.perform_now("support.example.com", "post", "users", nil, {"user" => {"name" => "Jane Doe", "email" => "jane@example.com"}})
    end
  end

  test "PUT user updates user" do
    stub_request(:put, "https://support.example.com/api/v2/users/4003.json")
      .with(
        basic_auth: ["user@example.com/token", "token"],
        body: {user: {name: "Updated Name"}}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
      .to_return(status: 200, body: {user: {id: 4003, name: "Updated Name"}}.to_json, headers: {"Content-Type" => "application/json"})

    # PUT is async, so it doesn't return a result
    assert_nothing_raised do
      ZendeskProxyJob.perform_now("support.example.com", "put", "users", 4003, {"user" => {"name" => "Updated Name"}})
    end
  end

  test "PATCH user updates user partially" do
    stub_request(:patch, "https://support.example.com/api/v2/users/4004.json")
      .with(
        basic_auth: ["user@example.com/token", "token"],
        body: {user: {role: "agent"}}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
      .to_return(status: 200, body: {user: {id: 4004, role: "agent"}}.to_json, headers: {"Content-Type" => "application/json"})

    # PATCH is async, so it doesn't return a result
    assert_nothing_raised do
      ZendeskProxyJob.perform_now("support.example.com", "patch", "users", 4004, {"user" => {"role" => "agent"}})
    end
  end

  test "DELETE user deletes user" do
    stub_request(:delete, "https://support.example.com/api/v2/users/4005.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(status: 200, body: {user: {id: 4005, active: false}}.to_json, headers: {"Content-Type" => "application/json"})

    result = ZendeskProxyJob.perform_now("support.example.com", "delete", "users", 4005, nil)
    assert_equal 200, result[0]
    assert_equal 4005, result[1]["user"]["id"]
  end

  # ========== Error Handling Tests ==========

  test "does nothing when no desk for domain" do
    stub_request(:get, %r{support\.unknown\.com/api/v2/tickets})
      .to_return(status: 200, body: {ticket: {id: 1}}.to_json)

    assert_no_difference "ZendeskTicket.count" do
      ZendeskProxyJob.perform_now("support.unknown.com", "get", "tickets", 999, nil)
    end
  end

  test "does nothing when desk is inactive" do
    @desk.update!(active: false)
    stub_ticket_get(3004, {id: 3004, subject: "Inactive desk", status: "open"})

    assert_no_difference "ZendeskTicket.count" do
      ZendeskProxyJob.perform_now("support.example.com", "get", "tickets", 3004, nil)
    end

    # Should not make any API request when desk is inactive
    assert_not_requested :get, "https://support.example.com/api/v2/tickets/3004.json"
  end

  test "waits when desk is rate limited" do
    @desk.update_column(:wait_till, Time.now.to_i + 1)
    stub_ticket_get(3003, {id: 3003, subject: "Rate limited", status: "open"})

    assert_no_difference "ZendeskTicket.count" do
      ZendeskProxyJob.perform_now("support.example.com", "get", "tickets", 3003, nil)
    end
  end

  test "handles errors gracefully for GET requests and returns error response" do
    stub_request(:get, "https://support.example.com/api/v2/tickets/9999.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(status: 404, body: {error: "Not Found"}.to_json, headers: {"Content-Type" => "application/json"})

    result = ZendeskProxyJob.perform_now("support.example.com", "get", "tickets", 9999, nil)
    assert_equal 404, result[0]
  end

  test "RecordInvalid (e.g. duplicate email) does not raise for async, returns 422 for sync" do
    error_body = {"email" => [{"description" => "Email: test@example.com is already being used by another user", "error" => "DuplicateValue"}]}
    stub_request(:post, "https://support.example.com/api/v2/users.json")
      .with(
        basic_auth: ["user@example.com/token", "token"],
        body: {user: {name: "Test", email: "test@example.com"}}.to_json
      )
      .to_return(status: 422, body: error_body.to_json, headers: {"Content-Type" => "application/json"})

    assert_nothing_raised do
      ZendeskProxyJob.perform_now("support.example.com", "post", "users", nil, {"user" => {"name" => "Test", "email" => "test@example.com"}})
    end
  end

  test "RecordInvalid returns 422 for synchronous GET (validation response, not server error)" do
    error_body = {"email" => [{"description" => "Email: test@example.com is already being used", "error" => "DuplicateValue"}]}
    stub_request(:get, "https://support.example.com/api/v2/users/4006.json")
      .with(basic_auth: ["user@example.com/token", "token"])
      .to_return(status: 422, body: error_body.to_json, headers: {"Content-Type" => "application/json"})

    result = ZendeskProxyJob.perform_now("support.example.com", "get", "users", 4006, nil)
    assert_equal 422, result[0]
    assert_equal "ZendeskAPI::Error::RecordInvalid", result[1][:error_class]
  end

  test "raises error for invalid resource_type" do
    assert_raises(ArgumentError) do
      ZendeskProxyJob.perform_now("support.example.com", "get", "invalid_resource", 123, nil)
    end
  end
end
