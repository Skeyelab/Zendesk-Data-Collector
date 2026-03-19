# frozen_string_literal: true

require "test_helper"

class PiiMaskableTest < ActiveSupport::TestCase
  test "masked_req_email returns masked email" do
    ticket = zendesk_tickets(:one)
    ticket.req_email = "customer@example.com"

    assert_equal "c***@example.com", ticket.masked_req_email
  end

  test "masked_req_email handles nil" do
    ticket = zendesk_tickets(:one)
    ticket.req_email = nil

    assert_nil ticket.masked_req_email
  end

  test "masked_req_name returns masked name" do
    ticket = zendesk_tickets(:one)
    ticket.req_name = "John Doe"

    assert_equal "J*** D***", ticket.masked_req_name
  end

  test "masked_req_name handles nil" do
    ticket = zendesk_tickets(:one)
    ticket.req_name = nil

    assert_nil ticket.masked_req_name
  end

  test "masked_assignee_name returns masked name" do
    ticket = zendesk_tickets(:one)
    ticket.assignee_name = "Support Agent"

    assert_equal "S*** A***", ticket.masked_assignee_name
  end

  test "masked_assignee_name handles nil" do
    ticket = zendesk_tickets(:one)
    ticket.assignee_name = nil

    assert_nil ticket.masked_assignee_name
  end

  test "pii_redacted_raw_data redacts requester info" do
    ticket = zendesk_tickets(:one)
    ticket.raw_data = {
      "requester" => {
        "name" => "John Customer",
        "email" => "john@customer.com",
        "phone" => "555-1234"
      }
    }

    redacted = ticket.pii_redacted_raw_data

    assert_equal "J*** C***", redacted["requester"]["name"]
    assert_equal "j***@customer.com", redacted["requester"]["email"]
    assert_equal "***-1234", redacted["requester"]["phone"]
  end

  test "pii_redacted_raw_data redacts comments" do
    ticket = zendesk_tickets(:one)
    ticket.raw_data = {
      "comments" => [
        {
          "id" => 1,
          "body" => "This is a sensitive comment",
          "author" => {"name" => "John", "id" => 123}
        }
      ]
    }

    redacted = ticket.pii_redacted_raw_data

    assert_match(/\[Content hidden/, redacted["comments"][0]["body"])
    assert_equal "J***", redacted["comments"][0]["author"]["name"]
  end

  test "pii_redacted_raw_data does not modify original raw_data" do
    ticket = zendesk_tickets(:one)
    ticket.raw_data = {
      "requester" => {
        "name" => "John Doe",
        "email" => "john@example.com"
      }
    }

    original_data = ticket.raw_data.deep_dup
    ticket.pii_redacted_raw_data

    # Original raw_data should not be modified
    assert_equal original_data, ticket.raw_data
  end

  test "comments_count returns number of comments" do
    ticket = zendesk_tickets(:one)
    ticket.raw_data = {
      "comments" => [
        {"id" => 1, "body" => "Comment 1"},
        {"id" => 2, "body" => "Comment 2"},
        {"id" => 3, "body" => "Comment 3"}
      ]
    }

    assert_equal 3, ticket.comments_count
  end

  test "comments_count returns 0 when no comments" do
    ticket = zendesk_tickets(:one)
    ticket.raw_data = {}

    assert_equal 0, ticket.comments_count
  end

  test "comments_count returns 0 when raw_data is nil" do
    ticket = zendesk_tickets(:one)
    ticket.raw_data = nil

    assert_equal 0, ticket.comments_count
  end

  test "has_comments? returns true when comments exist" do
    ticket = zendesk_tickets(:one)
    ticket.raw_data = {
      "comments" => [{"id" => 1, "body" => "Comment"}]
    }

    assert ticket.has_comments?
  end

  test "has_comments? returns false when no comments" do
    ticket = zendesk_tickets(:one)
    ticket.raw_data = {}

    assert_not ticket.has_comments?
  end

  test "comments_metadata returns metadata without content" do
    ticket = zendesk_tickets(:one)
    ticket.raw_data = {
      "comments" => [
        {
          "id" => 1,
          "author_id" => 123,
          "created_at" => "2024-01-01T00:00:00Z",
          "public" => true,
          "type" => "Comment",
          "body" => "This is a sensitive comment body"
        },
        {
          "id" => 2,
          "author_id" => 456,
          "created_at" => "2024-01-02T00:00:00Z",
          "public" => false,
          "type" => "Comment",
          "body" => "Another sensitive comment"
        }
      ]
    }

    metadata = ticket.comments_metadata

    assert_equal 2, metadata.length

    # First comment metadata
    assert_equal 1, metadata[0][:id]
    assert_equal 123, metadata[0][:author_id]
    assert_equal "2024-01-01T00:00:00Z", metadata[0][:created_at]
    assert metadata[0][:public]
    assert_equal "Comment", metadata[0][:type]
    assert_equal 32, metadata[0][:body_length]

    # Second comment metadata
    assert_equal 2, metadata[1][:id]
    assert_equal 456, metadata[1][:author_id]
    assert_not metadata[1][:public]
    assert_equal 26, metadata[1][:body_length]

    # Ensure body content is NOT included
    assert_nil metadata[0][:body]
    assert_nil metadata[1][:body]
  end

  test "comments_metadata returns empty array when no comments" do
    ticket = zendesk_tickets(:one)
    ticket.raw_data = {}

    assert_equal [], ticket.comments_metadata
  end
end
