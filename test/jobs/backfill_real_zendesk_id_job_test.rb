require "test_helper"

class BackfillRealZendeskIdJobTest < ActiveJob::TestCase
  def setup
    @ticket = ZendeskTicket.create!(
      zendesk_id: 5001,
      domain: "test.zendesk.com",
      subject: "Ticket A",
      status: "open",
      raw_data: {"id" => 5001}
    )

    @ticket2 = ZendeskTicket.create!(
      zendesk_id: 5002,
      domain: "test.zendesk.com",
      subject: "Ticket B",
      status: "open",
      raw_data: {"id" => 5002}
    )

    # Comments without real_zendesk_id (simulate pre-migration rows)
    ZendeskTicketComment.insert_all([
      {zendesk_ticket_id: @ticket.id, zendesk_comment_id: 1, body: "c1", plain_body: "c1", created_at: Time.current},
      {zendesk_ticket_id: @ticket.id, zendesk_comment_id: 2, body: "c2", plain_body: "c2", created_at: Time.current},
      {zendesk_ticket_id: @ticket2.id, zendesk_comment_id: 3, body: "c3", plain_body: "c3", created_at: Time.current}
    ])
  end

  test "backfills real_zendesk_id for rows where it is NULL" do
    assert_equal 3, ZendeskTicketComment.where(real_zendesk_id: nil).count

    BackfillRealZendeskIdJob.perform_now

    assert_equal 0, ZendeskTicketComment.where(real_zendesk_id: nil).count

    ZendeskTicketComment.where(zendesk_ticket_id: @ticket.id).each do |c|
      assert_equal @ticket.zendesk_id, c.real_zendesk_id
    end

    assert_equal @ticket2.zendesk_id,
      ZendeskTicketComment.find_by(zendesk_comment_id: 3).real_zendesk_id
  end

  test "skips rows that already have real_zendesk_id set" do
    ZendeskTicketComment.where(zendesk_comment_id: 1).update_all(real_zendesk_id: @ticket.zendesk_id)

    BackfillRealZendeskIdJob.perform_now

    assert_equal 0, ZendeskTicketComment.where(real_zendesk_id: nil).count
  end

  test "is idempotent when run twice" do
    BackfillRealZendeskIdJob.perform_now
    BackfillRealZendeskIdJob.perform_now

    assert_equal 0, ZendeskTicketComment.where(real_zendesk_id: nil).count
  end

  test "processes in batches and enqueues next batch when more rows remain" do
    assert_enqueued_with(job: BackfillRealZendeskIdJob) do
      BackfillRealZendeskIdJob.perform_now(batch_size: 1)
    end
  end

  test "does not enqueue next batch when all rows are backfilled" do
    assert_no_enqueued_jobs only: BackfillRealZendeskIdJob do
      BackfillRealZendeskIdJob.perform_now(batch_size: 10)
    end
  end

  test "does nothing and logs complete when no NULL rows exist" do
    ZendeskTicketComment.update_all(real_zendesk_id: 9999)

    assert_no_enqueued_jobs only: BackfillRealZendeskIdJob do
      assert_nothing_raised { BackfillRealZendeskIdJob.perform_now }
    end
  end
end
