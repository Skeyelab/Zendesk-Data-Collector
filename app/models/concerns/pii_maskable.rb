# frozen_string_literal: true

# Concern for adding PII masking capabilities to models
# Include this in models that contain PII fields
#
# Example:
#   class ZendeskTicket < ApplicationRecord
#     include PiiMaskable
#   end
#
#   ticket.req_email # => "john@example.com" (unmasked)
#   ticket.masked_req_email # => "j***@example.com" (masked)
#   ticket.pii_redacted_raw_data # => { ... redacted ... }
module PiiMaskable
  extend ActiveSupport::Concern

  # Returns a masked version of the requester email
  # @return [String, nil] Masked email address
  def masked_req_email
    return nil if req_email.nil?
    mask_email_internal(req_email)
  end

  # Returns a masked version of the requester name
  # @return [String, nil] Masked name
  def masked_req_name
    return nil if req_name.nil?
    mask_name_internal(req_name)
  end

  # Returns a masked version of the assignee name
  # @return [String, nil] Masked name
  def masked_assignee_name
    return nil if assignee_name.nil?
    mask_name_internal(assignee_name)
  end

  # Returns a version of raw_data with PII redacted
  # Useful for displaying in admin interfaces
  # @return [Hash] Redacted raw_data
  def pii_redacted_raw_data
    return {} if raw_data.nil?

    redacted = raw_data.deep_dup

    # Redact requester information
    if redacted["requester"].is_a?(Hash)
      redacted["requester"]["name"] = mask_name_internal(redacted["requester"]["name"])
      redacted["requester"]["email"] = mask_email_internal(redacted["requester"]["email"])
      redacted["requester"]["phone"] = mask_phone_internal(redacted["requester"]["phone"])
    end

    # Redact assignee information
    if redacted["assignee"].is_a?(Hash)
      redacted["assignee"]["name"] = mask_name_internal(redacted["assignee"]["name"])
      redacted["assignee"]["email"] = mask_email_internal(redacted["assignee"]["email"])
    end

    # Redact submitter information
    if redacted["submitter"].is_a?(Hash)
      redacted["submitter"]["name"] = mask_name_internal(redacted["submitter"]["name"])
      redacted["submitter"]["email"] = mask_email_internal(redacted["submitter"]["email"])
    end

    # Redact description
    if redacted["description"].present?
      redacted["description"] = mask_text_content_internal(redacted["description"])
    end

    # Redact comments
    if redacted["comments"].is_a?(Array)
      redacted["comments"] = redacted["comments"].map do |comment|
        next comment unless comment.is_a?(Hash)

        comment_copy = comment.dup
        if comment["body"].present?
          comment_copy["body"] = mask_text_content_internal(comment["body"])
        end
        if comment["plain_body"].present?
          comment_copy["plain_body"] = mask_text_content_internal(comment["plain_body"])
        end
        if comment["html_body"].present?
          comment_copy["html_body"] = mask_text_content_internal(comment["html_body"])
        end

        # Mask author name if present
        if comment_copy["author"].is_a?(Hash) && comment_copy["author"]["name"].present?
          comment_copy["author"]["name"] = mask_name_internal(comment_copy["author"]["name"])
        end

        comment_copy
      end
    end

    # Redact via source (may contain email/phone in from field)
    if redacted["via"].is_a?(Hash) && redacted["via"]["source"].is_a?(Hash)
      from_value = redacted["via"]["source"]["from"]
      if from_value.present?
        # Try to detect if it's an email
        if from_value.to_s.include?("@")
          redacted["via"]["source"]["from"] = mask_email_internal(from_value)
        else
          redacted["via"]["source"]["from"] = "[Redacted]"
        end
      end
    end

    # Redact custom fields that might contain PII (long text values)
    if redacted["custom_fields"].is_a?(Array)
      redacted["custom_fields"] = redacted["custom_fields"].map do |field|
        next field unless field.is_a?(Hash)

        field_copy = field.dup
        # Only redact string values longer than 50 chars (likely to contain PII)
        if field_copy["value"].is_a?(String) && field_copy["value"].length > 50
          field_copy["value"] = mask_text_content_internal(field_copy["value"], show_length: true)
        end
        field_copy
      end
    end

    redacted
  end

  # Returns count of comments without exposing content
  # @return [Integer] Number of comments
  def comments_count
    return 0 unless raw_data.is_a?(Hash) && raw_data["comments"].is_a?(Array)
    raw_data["comments"].length
  end

  # Returns whether the ticket has comments
  # @return [Boolean]
  def has_comments?
    comments_count > 0
  end

  # Returns a summary of comment metadata without content
  # Useful for displaying comment info without exposing PII
  # @return [Array<Hash>] Array of comment metadata
  def comments_metadata
    return [] unless raw_data.is_a?(Hash) && raw_data["comments"].is_a?(Array)

    raw_data["comments"].map do |comment|
      {
        id: comment["id"],
        author_id: comment["author_id"],
        created_at: comment["created_at"],
        public: comment["public"],
        type: comment["type"],
        body_length: comment["body"]&.length || 0
      }
    end
  end

  private

  # Internal masking methods - duplicated from helper to avoid dependencies
  # These could be refactored to use a shared service if preferred

  def mask_email_internal(email)
    return nil if email.nil?
    return email if email.blank?

    parts = email.to_s.split("@")
    return email if parts.length != 2

    local = parts[0]
    domain = parts[1]

    return email if local.blank? || domain.blank?

    masked_local = "#{local[0]}***"
    "#{masked_local}@#{domain}"
  end

  def mask_name_internal(name)
    return nil if name.nil?
    return name if name.blank?

    words = name.to_s.split(/\s+/)
    masked_words = words.map do |word|
      next if word.blank?
      "#{word[0]}***"
    end

    masked_words.compact.join(" ")
  end

  def mask_phone_internal(phone)
    return nil if phone.nil?
    return phone if phone.blank?

    # Extract digits only
    digits = phone.to_s.gsub(/\D/, "")
    return "***" if digits.length < 4

    last_four = digits[-4..]
    "***-#{last_four}"
  end

  def mask_text_content_internal(text, show_length: true)
    return nil if text.nil?
    return "[Empty]" if text.blank?

    length = text.to_s.length
    if show_length
      "[Content hidden - #{length} characters]"
    else
      "[Content hidden]"
    end
  end
end
