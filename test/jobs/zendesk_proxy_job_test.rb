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

  test "GET ticket proxies to Zendesk and does not create ZendeskTicket" do
    stub_ticket_get(3001, {id: 3001, subject: "Proxy get", status: "open"})

    assert_no_difference "ZendeskTicket.count" do
      ZendeskProxyJob.perform_now("support.example.com", "get", 3001, nil)
    end
  end

  test "PUT ticket proxies to Zendesk and does not create ZendeskTicket" do
    stub_ticket_put(3002)

    assert_no_difference "ZendeskTicket.count" do
      ZendeskProxyJob.perform_now("support.example.com", "put", 3002, {"ticket" => {"status" => "solved"}})
    end
  end

  test "does nothing when no desk for domain" do
    stub_request(:get, %r{support\.unknown\.com/api/v2/tickets})
      .to_return(status: 200, body: {ticket: {id: 1}}.to_json)

    assert_no_difference "ZendeskTicket.count" do
      ZendeskProxyJob.perform_now("support.unknown.com", "get", 999, nil)
    end
  end

  test "waits when desk is rate limited" do
    @desk.update_column(:wait_till, Time.now.to_i + 1)
    stub_ticket_get(3003, {id: 3003, subject: "Rate limited", status: "open"})

    assert_no_difference "ZendeskTicket.count" do
      ZendeskProxyJob.perform_now("support.example.com", "get", 3003, nil)
    end
  end
end
