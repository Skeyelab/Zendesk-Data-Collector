require "test_helper"

class MigrateTicketCommentsJobTest < ActiveJob::TestCase
  def setup
    @ticket = ZendeskTicket.create!(
      zendesk_id: 1001,
      domain: "test.zendesk.com",
      subject: "Ticket with comments",
      status: "open",
      raw_data: {
        "id" => 1001,
        "comments" => [
          {"id" => 10, "body" => "First comment", "plain_body" => "First comment", "author_id" => 55, "public" => true, "created_at" => "2024-01-01T10:00:00Z"},
          {"id" => 11, "body" => "Second comment", "plain_body" => "Second comment", "author_id" => 56, "public" => false, "created_at" => "2024-01-02T10:00:00Z"}
        ]
      }
    )

    @ticket_no_comments = ZendeskTicket.create!(
      zendesk_id: 1002,
      domain: "test.zendesk.com",
      subject: "Ticket without comments",
      status: "open",
      raw_data: {"id" => 1002, "subject" => "Ticket without comments"}
    )
  end

  test "migrates comments from raw_data into zendesk_ticket_comments" do
    assert_difference "ZendeskTicketComment.count", 2 do
      MigrateTicketCommentsJob.perform_now
    end

    first = ZendeskTicketComment.find_by(zendesk_comment_id: 10)
    assert_not_nil first
    assert_equal @ticket.id, first.zendesk_ticket_id
    assert_equal "First comment", first.body
    assert_equal 55, first.author_id
    assert_equal true, first.public

    second = ZendeskTicketComment.find_by(zendesk_comment_id: 11)
    assert_not_nil second
    assert_equal false, second.public
  end

  test "strips comments from raw_data after migrating" do
    MigrateTicketCommentsJob.perform_now

    @ticket.reload
    assert_nil @ticket.raw_data["comments"]
    assert_equal 1001, @ticket.raw_data["id"]
  end

  test "does not touch tickets without comments in raw_data" do
    MigrateTicketCommentsJob.perform_now

    @ticket_no_comments.reload
    assert_equal({"id" => 1002, "subject" => "Ticket without comments"}, @ticket_no_comments.raw_data)
  end

  test "is idempotent when run twice" do
    MigrateTicketCommentsJob.perform_now

    assert_no_difference "ZendeskTicketComment.count" do
      MigrateTicketCommentsJob.perform_now
    end
  end

  test "skips comments with no id" do
    @ticket.update_columns(raw_data: @ticket.raw_data.merge(
      "comments" => [{"id" => nil, "body" => "Bad comment"}, {"id" => 20, "body" => "Good comment", "author_id" => 1, "created_at" => "2024-01-01T00:00:00Z"}]
    ))

    assert_difference "ZendeskTicketComment.count", 1 do
      MigrateTicketCommentsJob.perform_now
    end

    assert_not_nil ZendeskTicketComment.find_by(zendesk_comment_id: 20)
  end

  test "enqueues next batch when more tickets exist" do
    extra_ticket = ZendeskTicket.create!(
      zendesk_id: 1003,
      domain: "test.zendesk.com",
      subject: "Extra",
      status: "open",
      raw_data: {"comments" => [{"id" => 99, "body" => "Extra comment", "author_id" => 1, "created_at" => "2024-01-01T00:00:00Z"}]}
    )

    assert_enqueued_with(job: MigrateTicketCommentsJob) do
      MigrateTicketCommentsJob.perform_now(batch_size: 1)
    end

    extra_ticket.destroy
  end
end
