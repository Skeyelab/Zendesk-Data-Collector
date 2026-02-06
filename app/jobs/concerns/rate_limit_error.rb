# frozen_string_literal: true

# Custom exception for Zendesk API rate limit (429) errors.
# This provides better semantics than string matching on generic exceptions.
#
# Usage:
#   raise RateLimitError.new("Rate limit exceeded", response)
#   rescue RateLimitError => e
#     # Handle rate limit specifically
class RateLimitError < StandardError
  attr_reader :response

  def initialize(message = "Rate limit exceeded (429)", response = nil)
    super(message)
    @response = response
  end
end
