require 'test_helper'

class DeskTest < ActiveSupport::TestCase
  def setup
    @desk = Desk.new(
      domain: 'test.zendesk.com',
      user: 'test@example.com',
      token: 'secret_token_123'
    )
  end

  test "should have encrypted token" do
    @desk.save!
    raw_token = Desk.connection.select_value("SELECT token FROM desks WHERE id = #{@desk.id}")
    assert raw_token.present?
    assert_not_equal 'secret_token_123', raw_token
    assert_equal 'secret_token_123', @desk.reload.token
  end

  test "should set default values on initialization" do
    desk = Desk.new
    assert_equal 0, desk.last_timestamp
    assert_equal 0, desk.last_timestamp_event
    assert_equal 0, desk.wait_till
    assert_equal 0, desk.wait_till_event
    assert_equal false, desk.active
    assert_equal false, desk.queued
  end

  test "should not override persisted default values" do
    @desk.save!
    @desk.reload
    assert_equal 0, @desk.last_timestamp
    @desk.last_timestamp = 100
    @desk.save!
    @desk.reload
    assert_equal 100, @desk.last_timestamp
  end

  test "ready_to_go scope returns desks ready for processing" do
    # Create a desk that should be ready
    ready_desk = Desk.create!(
      domain: 'ready.zendesk.com',
      user: 'ready@example.com',
      token: 'token',
      last_timestamp: Time.now.to_i - 600, # 10 minutes ago
      wait_till: Time.now.to_i - 100, # waited already
      active: true,
      queued: false
    )

    # Create a desk that should NOT be ready (too recent)
    not_ready_recent = Desk.create!(
      domain: 'recent.zendesk.com',
      user: 'recent@example.com',
      token: 'token',
      last_timestamp: Time.now.to_i - 100, # too recent
      wait_till: Time.now.to_i - 100,
      active: true,
      queued: false
    )

    # Create a desk that should NOT be ready (still waiting)
    not_ready_waiting = Desk.create!(
      domain: 'waiting.zendesk.com',
      user: 'waiting@example.com',
      token: 'token',
      last_timestamp: Time.now.to_i - 600,
      wait_till: Time.now.to_i + 100, # still waiting
      active: true,
      queued: false
    )

    # Create a desk that should NOT be ready (inactive)
    not_ready_inactive = Desk.create!(
      domain: 'inactive.zendesk.com',
      user: 'inactive@example.com',
      token: 'token',
      last_timestamp: Time.now.to_i - 600,
      wait_till: Time.now.to_i - 100,
      active: false,
      queued: false
    )

    # Create a desk that should NOT be ready (already queued)
    not_ready_queued = Desk.create!(
      domain: 'queued.zendesk.com',
      user: 'queued@example.com',
      token: 'token',
      last_timestamp: Time.now.to_i - 600,
      wait_till: Time.now.to_i - 100,
      active: true,
      queued: true
    )

    ready_desks = Desk.readyToGo
    assert_includes ready_desks, ready_desk
    assert_not_includes ready_desks, not_ready_recent
    assert_not_includes ready_desks, not_ready_waiting
    assert_not_includes ready_desks, not_ready_inactive
    assert_not_includes ready_desks, not_ready_queued
  end

  test "should validate domain presence" do
    @desk.domain = nil
    assert_not @desk.valid?
    assert_includes @desk.errors[:domain], "can't be blank"
  end

  test "should validate domain uniqueness" do
    @desk.save!
    duplicate = Desk.new(
      domain: 'test.zendesk.com',
      user: 'other@example.com',
      token: 'other_token'
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:domain], "has already been taken"
  end

  test "should validate user presence" do
    @desk.user = nil
    assert_not @desk.valid?
    assert_includes @desk.errors[:user], "can't be blank"
  end

  test "should validate token presence" do
    @desk.token = nil
    assert_not @desk.valid?
    assert_includes @desk.errors[:token], "can't be blank"
  end
end
