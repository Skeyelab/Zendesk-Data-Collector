# frozen_string_literal: true

require "test_helper"

class ZendeskClientServiceTest < ActiveSupport::TestCase
  test "persist_wait_till_from_429 sets desk wait_till via update_all and respects Retry-After" do
    desk = Desk.create!(
      domain: "test.zendesk.com",
      user: "test@example.com",
      token: "token",
      last_timestamp: 0,
      active: true,
      queued: false
    )
    env = {status: 429, response_headers: {"Retry-After" => "42"}}

    ZendeskClientService.persist_wait_till_from_429(desk, env)

    desk.reload
    assert desk.wait_till > Time.now.to_i
    assert_in_delta 42, desk.wait_till - Time.now.to_i, 2
  end

  test "persist_wait_till_from_429 does nothing when status is not 429" do
    desk = Desk.create!(
      domain: "test.zendesk.com",
      user: "test@example.com",
      token: "token",
      last_timestamp: 0,
      active: true,
      queued: false
    )
    desk.update_column(:wait_till, 0)
    env = {status: 200}

    ZendeskClientService.persist_wait_till_from_429(desk, env)

    desk.reload
    assert_equal 0, desk.wait_till
  end

  test "persist_wait_till_from_429 succeeds even when desk would fail validation" do
    desk = Desk.create!(
      domain: "test.zendesk.com",
      user: "test@example.com",
      token: "token",
      last_timestamp: 0,
      active: true,
      queued: false
    )
    desk.update_columns(domain: nil) # invalid state; save! would fail
    env = {status: 429, response_headers: {"Retry-After" => "5"}}

    assert_nothing_raised do
      ZendeskClientService.persist_wait_till_from_429(desk, env)
    end

    # update_all bypasses validations and updates by id
    assert Desk.where(id: desk.id).pluck(:wait_till).first > Time.now.to_i
  end
end
