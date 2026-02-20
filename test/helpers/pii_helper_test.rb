# frozen_string_literal: true

require "test_helper"

class PiiHelperTest < ActionView::TestCase
  include PiiHelper

  test "mask_email masks email addresses correctly" do
    assert_equal "j***@example.com", mask_email("john.doe@example.com")
    assert_equal "a***@test.co", mask_email("admin@test.co")
    assert_equal "u***@company.org", mask_email("user@company.org")
  end

  test "mask_email handles edge cases" do
    assert_nil mask_email(nil)
    assert_equal "", mask_email("")
    assert_equal "invalid", mask_email("invalid") # No @ symbol
    assert_equal "@domain.com", mask_email("@domain.com") # Empty local part
  end

  test "mask_email preserves domain" do
    email = "test@example.com"
    masked = mask_email(email)
    assert masked.end_with?("@example.com"), "Domain should be preserved"
  end

  test "mask_name masks names correctly" do
    assert_equal "J*** D***", mask_name("John Doe")
    assert_equal "M***", mask_name("Mary")
    assert_equal "J*** Q*** P***", mask_name("John Quincy Public")
  end

  test "mask_name handles edge cases" do
    assert_nil mask_name(nil)
    assert_equal "", mask_name("")
    assert_equal "A***", mask_name("A") # Single character
    assert_equal "A*** B***", mask_name("A B") # Single char names
  end

  test "mask_name handles extra whitespace" do
    assert_equal "J*** D***", mask_name("John  Doe")
    assert_equal "J*** D***", mask_name("  John Doe  ")
  end

  test "mask_phone masks phone numbers correctly" do
    assert_equal "***-4567", mask_phone("+1-555-123-4567")
    assert_equal "***-4567", mask_phone("5551234567")
    assert_equal "***-0000", mask_phone("123-456-0000")
  end

  test "mask_phone handles edge cases" do
    assert_nil mask_phone(nil)
    assert_equal "***-4567", mask_phone("(555) 123-4567")
    assert_equal "***", mask_phone("123") # Less than 4 digits
    assert_equal "***-4567", mask_phone("abc-555-123-4567") # Letters mixed in
  end

  test "mask_text_content masks text with length" do
    text = "This is some sensitive information"
    masked = mask_text_content(text)
    assert_match(/\[Content hidden - \d+ characters\]/, masked)
    assert_match(/35 characters/, masked) # Actual length
  end

  test "mask_text_content masks text without length" do
    text = "Sensitive data"
    masked = mask_text_content(text, show_length: false)
    assert_equal "[Content hidden]", masked
  end

  test "mask_text_content handles edge cases" do
    assert_nil mask_text_content(nil)
    assert_equal "[Empty]", mask_text_content("")
    assert_equal "[Empty]", mask_text_content("   ")
  end

  test "redact_raw_data_pii redacts requester information" do
    raw_data = {
      "requester" => {
        "name" => "John Doe",
        "email" => "john@example.com",
        "phone" => "555-123-4567",
        "id" => 12345
      }
    }

    redacted = redact_raw_data_pii(raw_data)

    assert_equal "J*** D***", redacted["requester"]["name"]
    assert_equal "j***@example.com", redacted["requester"]["email"]
    assert_equal "***-4567", redacted["requester"]["phone"]
    assert_equal 12345, redacted["requester"]["id"] # IDs should not be masked
  end

  test "redact_raw_data_pii redacts assignee information" do
    raw_data = {
      "assignee" => {
        "name" => "Support Agent",
        "email" => "agent@company.com",
        "id" => 67890
      }
    }

    redacted = redact_raw_data_pii(raw_data)

    assert_equal "S*** A***", redacted["assignee"]["name"]
    assert_equal "a***@company.com", redacted["assignee"]["email"]
    assert_equal 67890, redacted["assignee"]["id"]
  end

  test "redact_raw_data_pii redacts description" do
    raw_data = {
      "description" => "My account is having issues with password reset"
    }

    redacted = redact_raw_data_pii(raw_data)

    assert_match(/\[Content hidden/, redacted["description"])
    assert_match(/characters\]/, redacted["description"])
  end

  test "redact_raw_data_pii redacts comments" do
    raw_data = {
      "comments" => [
        {
          "id" => 1,
          "body" => "This is a comment with sensitive info",
          "author" => {"name" => "John Doe", "id" => 123}
        },
        {
          "id" => 2,
          "body" => "Another comment",
          "author" => {"name" => "Jane Smith", "id" => 456}
        }
      ]
    }

    redacted = redact_raw_data_pii(raw_data)

    assert_equal 2, redacted["comments"].length
    assert_match(/\[Content hidden/, redacted["comments"][0]["body"])
    assert_equal "J*** D***", redacted["comments"][0]["author"]["name"]
    assert_match(/\[Content hidden/, redacted["comments"][1]["body"])
    assert_equal "J*** S***", redacted["comments"][1]["author"]["name"]
  end

  test "redact_raw_data_pii redacts via source from field" do
    raw_data = {
      "via" => {
        "source" => {
          "from" => "customer@example.com",
          "to" => "support@company.com"
        }
      }
    }

    redacted = redact_raw_data_pii(raw_data)

    assert_equal "c***@example.com", redacted["via"]["source"]["from"]
    # "to" should remain (it's our support address, not customer PII)
    assert_equal "support@company.com", redacted["via"]["source"]["to"]
  end

  test "redact_raw_data_pii handles nil and empty data" do
    assert_equal({}, redact_raw_data_pii(nil))
    assert_equal({}, redact_raw_data_pii({}))
  end

  test "redact_raw_data_pii does not modify original hash" do
    original = {
      "requester" => {
        "name" => "John Doe",
        "email" => "john@example.com"
      }
    }

    original_copy = original.deep_dup
    redact_raw_data_pii(original)

    # Original should not be modified
    assert_equal original_copy, original
  end

  test "redact_raw_data_pii redacts long custom field values" do
    raw_data = {
      "custom_fields" => [
        {"id" => 1, "value" => "short"},
        {"id" => 2, "value" => "This is a very long text field that likely contains sensitive information about the customer"},
        {"id" => 3, "value" => 12345}
      ]
    }

    redacted = redact_raw_data_pii(raw_data)

    # Short values and numbers should not be masked
    assert_equal "short", redacted["custom_fields"][0]["value"]
    assert_equal 12345, redacted["custom_fields"][2]["value"]

    # Long text should be masked
    assert_match(/\[Content hidden/, redacted["custom_fields"][1]["value"])
  end

  test "can_view_pii returns true by default" do
    # Default implementation for backwards compatibility
    assert can_view_pii?
  end
end
