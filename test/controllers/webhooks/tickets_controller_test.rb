require "test_helper"

class WebhooksTicketsControllerTest < ActionDispatch::IntegrationTest
  test "POST with domain and ticket_id enqueues ZendeskProxyJob (default get) and returns 202" do
    Desk.create!(
      domain: "support.example.com",
      user: "user@example.com",
      token: "token",
      active: true,
      queued: false
    )

    payload = {domain: "support.example.com", ticket_id: 2001}

    assert_enqueued_with(job: ZendeskProxyJob, args: ["support.example.com", "get", 2001, nil]) do
      post webhooks_tickets_path, params: payload, as: :json
    end

    assert_response :accepted
    assert_no_difference "ZendeskTicket.count" do
      # Ensure we never create rows
    end
  end

  test "POST with domain, method put, ticket_id and body enqueues ZendeskProxyJob and returns 202" do
    payload = {
      domain: "support.example.com",
      method: "put",
      ticket_id: 2002,
      body: {ticket: {status: "solved"}}
    }

    assert_enqueued_with(job: ZendeskProxyJob, args: ["support.example.com", "put", 2002, {"ticket" => {"status" => "solved"}}]) do
      post webhooks_tickets_path, params: payload, as: :json
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
      post webhooks_tickets_path, params: payload, as: :json
    end
    assert_response :accepted
  end

  test "POST without domain returns 422" do
    payload = {ticket_id: 1003, method: "get"}

    post webhooks_tickets_path, params: payload, as: :json

    assert_response :unprocessable_entity
  end

  test "POST with get/put but no ticket_id returns 422" do
    post webhooks_tickets_path, params: {domain: "support.example.com", method: "get"}, as: :json
    assert_response :unprocessable_entity

    post webhooks_tickets_path, params: {domain: "support.example.com", method: "put"}, as: :json
    assert_response :unprocessable_entity
  end

  test "POST with invalid method returns 422" do
    post webhooks_tickets_path, params: {domain: "support.example.com", ticket_id: 1, method: "delete"}, as: :json
    assert_response :unprocessable_entity
  end

  test "POST with invalid JSON returns 400 or 422" do
    post webhooks_tickets_path, params: "not json", headers: {"Content-Type" => "application/json"}

    assert_includes [400, 422], response.status
  end
end
