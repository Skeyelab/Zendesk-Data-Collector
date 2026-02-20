# frozen_string_literal: true

# Helper module for masking PII (Personally Identifiable Information) in the application.
# Provides utility methods to mask sensitive data like emails, names, and text content
# while maintaining some readability for legitimate use cases.
module PiiHelper
  # Masks an email address, showing only first character of local part and domain
  # Examples:
  #   john.doe@example.com => j***@example.com
  #   admin@test.co => a***@test.co
  #   nil => nil
  #
  # @param email [String, nil] The email address to mask
  # @return [String, nil] The masked email or nil if input is nil
  def mask_email(email)
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

  # Masks a person's name, showing only first character of each word
  # Examples:
  #   "John Doe" => "J*** D***"
  #   "Mary" => "M***"
  #   nil => nil
  #
  # @param name [String, nil] The name to mask
  # @return [String, nil] The masked name or nil if input is nil
  def mask_name(name)
    return nil if name.nil?
    return name if name.blank?

    words = name.to_s.split(/\s+/)
    masked_words = words.map do |word|
      next if word.blank?
      "#{word[0]}***"
    end

    masked_words.compact.join(" ")
  end

  # Masks a phone number, showing only last 4 digits
  # Examples:
  #   "+1-555-123-4567" => "***-4567"
  #   "5551234567" => "***4567"
  #   nil => nil
  #
  # @param phone [String, nil] The phone number to mask
  # @return [String, nil] The masked phone or nil if input is nil
  def mask_phone(phone)
    return nil if phone.nil?
    return phone if phone.blank?

    # Extract digits only
    digits = phone.to_s.gsub(/\D/, "")
    return "***" if digits.length < 4

    last_four = digits[-4..]
    "***-#{last_four}"
  end

  # Masks arbitrary text content by replacing with a summary
  # Useful for ticket descriptions and comments
  # Examples:
  #   "Long text here..." => "[Content hidden - 123 characters]"
  #   nil => nil
  #
  # @param text [String, nil] The text to mask
  # @param show_length [Boolean] Whether to show character count (default: true)
  # @return [String, nil] The masked text summary or nil if input is nil
  def mask_text_content(text, show_length: true)
    return nil if text.nil?
    return "[Empty]" if text.blank?

    length = text.to_s.length
    if show_length
      "[Content hidden - #{length} characters]"
    else
      "[Content hidden]"
    end
  end

  # Redacts PII from the raw_data JSONB field
  # Creates a deep copy and replaces sensitive fields with masked versions
  #
  # @param raw_data [Hash] The raw_data hash from ZendeskTicket
  # @return [Hash] A new hash with PII redacted
  def redact_raw_data_pii(raw_data)
    return {} if raw_data.nil? || !raw_data.is_a?(Hash)

    redacted = raw_data.deep_dup

    # Redact requester information
    if redacted["requester"].is_a?(Hash)
      redacted["requester"]["name"] = mask_name(redacted["requester"]["name"])
      redacted["requester"]["email"] = mask_email(redacted["requester"]["email"])
      redacted["requester"]["phone"] = mask_phone(redacted["requester"]["phone"])
    end

    # Redact assignee information
    if redacted["assignee"].is_a?(Hash)
      redacted["assignee"]["name"] = mask_name(redacted["assignee"]["name"])
      redacted["assignee"]["email"] = mask_email(redacted["assignee"]["email"])
    end

    # Redact submitter information
    if redacted["submitter"].is_a?(Hash)
      redacted["submitter"]["name"] = mask_name(redacted["submitter"]["name"])
      redacted["submitter"]["email"] = mask_email(redacted["submitter"]["email"])
    end

    # Redact description
    if redacted["description"].present?
      redacted["description"] = mask_text_content(redacted["description"])
    end

    # Redact comments
    if redacted["comments"].is_a?(Array)
      redacted["comments"] = redacted["comments"].map do |comment|
        next comment unless comment.is_a?(Hash)

        comment_copy = comment.dup
        comment_copy["body"] = mask_text_content(comment["body"]) if comment["body"].present?
        comment_copy["plain_body"] = mask_text_content(comment["plain_body"]) if comment["plain_body"].present?
        comment_copy["html_body"] = mask_text_content(comment["html_body"]) if comment["html_body"].present?

        # Mask author name if present
        if comment_copy["author"].is_a?(Hash)
          comment_copy["author"]["name"] = mask_name(comment_copy["author"]["name"])
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
          redacted["via"]["source"]["from"] = mask_email(from_value)
        else
          redacted["via"]["source"]["from"] = "[Redacted]"
        end
      end
    end

    # Redact custom fields that might contain PII
    # This is conservative - custom fields may or may not contain PII
    if redacted["custom_fields"].is_a?(Array)
      redacted["custom_fields"] = redacted["custom_fields"].map do |field|
        next field unless field.is_a?(Hash)

        field_copy = field.dup
        # Only redact string values, leave IDs and numbers alone
        if field_copy["value"].is_a?(String) && field_copy["value"].length > 50
          field_copy["value"] = mask_text_content(field_copy["value"])
        end
        field_copy
      end
    end

    redacted
  end

  # Checks if the current user can view unmasked PII
  # This should be overridden in ApplicationController or specific controllers
  # to implement proper role-based access control
  #
  # @return [Boolean] Whether the current user can view PII
  def can_view_pii?
    # Default implementation - should be overridden
    # For now, return true to maintain backwards compatibility
    true
  end

  # Helper to create a "Show PII" link or button
  # Returns HTML for a button to unmask PII if user has permission
  #
  # @param resource [ActiveRecord::Base] The resource to unmask
  # @param field [Symbol, String] The field name to unmask
  # @return [String, nil] HTML safe string or nil if user cannot unmask
  def unmask_pii_button(resource, field)
    return nil unless defined?(current_user) && current_user.respond_to?(:can_unmask_pii?)
    return nil unless current_user.can_unmask_pii?

    link_to "Show PII",
      "#",
      class: "unmask-pii-button",
      data: {
        resource_type: resource.class.name,
        resource_id: resource.id,
        field: field
      }
  end
end
