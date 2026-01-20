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

  test "stuck_queued scope finds desks queued for more than 5 minutes" do
    # Create a stuck desk (queued, active, updated more than 5 minutes ago)
    stuck_desk = Desk.create!(
      domain: 'stuck.zendesk.com',
      user: 'stuck@example.com',
      token: 'token',
      queued: true,
      active: true,
      updated_at: 10.minutes.ago
    )

    # Create a recently queued desk (should not be stuck)
    recent_desk = Desk.create!(
      domain: 'recent.zendesk.com',
      user: 'recent@example.com',
      token: 'token',
      queued: true,
      active: true,
      updated_at: 2.minutes.ago
    )

    # Create an inactive queued desk (should not be stuck)
    inactive_desk = Desk.create!(
      domain: 'inactive.zendesk.com',
      user: 'inactive@example.com',
      token: 'token',
      queued: true,
      active: false,
      updated_at: 10.minutes.ago
    )

    # Create a not queued desk (should not be stuck)
    not_queued_desk = Desk.create!(
      domain: 'notqueued.zendesk.com',
      user: 'notqueued@example.com',
      token: 'token',
      queued: false,
      active: true,
      updated_at: 10.minutes.ago
    )

    stuck_desks = Desk.stuck_queued
    assert_includes stuck_desks, stuck_desk
    assert_not_includes stuck_desks, recent_desk
    assert_not_includes stuck_desks, inactive_desk
    assert_not_includes stuck_desks, not_queued_desk
  end

  test "reset_stuck_queued_flags! resets stuck desks" do
    # Create stuck desks
    stuck_desk1 = Desk.create!(
      domain: 'stuck1.zendesk.com',
      user: 'stuck1@example.com',
      token: 'token',
      queued: true,
      active: true,
      updated_at: 10.minutes.ago
    )

    stuck_desk2 = Desk.create!(
      domain: 'stuck2.zendesk.com',
      user: 'stuck2@example.com',
      token: 'token',
      queued: true,
      active: true,
      updated_at: 15.minutes.ago
    )

    # Create a recently queued desk (should not be reset)
    recent_desk = Desk.create!(
      domain: 'recent.zendesk.com',
      user: 'recent@example.com',
      token: 'token',
      queued: true,
      active: true,
      updated_at: 2.minutes.ago
    )

    # Reset stuck flags
    reset_count = Desk.reset_stuck_queued_flags!

    assert_equal 2, reset_count
    assert_equal false, stuck_desk1.reload.queued
    assert_equal false, stuck_desk2.reload.queued
    assert_equal true, recent_desk.reload.queued
  end

  test "reset_stuck_queued_flags! returns 0 when no stuck desks" do
    # Create only recently queued desks
    Desk.create!(
      domain: 'recent.zendesk.com',
      user: 'recent@example.com',
      token: 'token',
      queued: true,
      active: true,
      updated_at: 2.minutes.ago
    )

    reset_count = Desk.reset_stuck_queued_flags!
    assert_equal 0, reset_count
  end
end
