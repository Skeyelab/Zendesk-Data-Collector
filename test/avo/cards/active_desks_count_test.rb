require "test_helper"

class Avo::Cards::ActiveDesksCountTest < ActiveSupport::TestCase
  def setup
    # Clean up any existing desks
    Desk.delete_all
  end

  test "should return zero when no desks exist" do
    card = Avo::Cards::ActiveDesksCount.new
    result = card.query

    assert_equal 0, result
  end

  test "should return zero when all desks are inactive" do
    Desk.create!(
      domain: "test1.zendesk.com",
      user: "user1@example.com",
      token: "token1",
      active: false
    )
    Desk.create!(
      domain: "test2.zendesk.com",
      user: "user2@example.com",
      token: "token2",
      active: false
    )

    card = Avo::Cards::ActiveDesksCount.new
    result = card.query

    assert_equal 0, result
  end

  test "should count only active desks" do
    Desk.create!(
      domain: "test1.zendesk.com",
      user: "user1@example.com",
      token: "token1",
      active: true
    )
    Desk.create!(
      domain: "test2.zendesk.com",
      user: "user2@example.com",
      token: "token2",
      active: false
    )
    Desk.create!(
      domain: "test3.zendesk.com",
      user: "user3@example.com",
      token: "token3",
      active: true
    )

    card = Avo::Cards::ActiveDesksCount.new
    result = card.query

    assert_equal 2, result
  end

  test "should not count queued desks as active" do
    Desk.create!(
      domain: "test1.zendesk.com",
      user: "user1@example.com",
      token: "token1",
      active: true,
      queued: false
    )
    Desk.create!(
      domain: "test2.zendesk.com",
      user: "user2@example.com",
      token: "token2",
      active: true,
      queued: true
    )

    card = Avo::Cards::ActiveDesksCount.new
    result = card.query

    assert_equal 1, result
  end
end
