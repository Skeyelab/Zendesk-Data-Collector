# frozen_string_literal: true

# Utility module for extracting nested hash fields into model attributes.
# This module provides a consistent pattern for extracting fields from API responses
# and assigning them to model attributes, reducing code duplication.
#
# Example usage:
#   class MyModel < ApplicationRecord
#     include FieldExtractor
#
#     def process_data(data)
#       extract_hash_fields(data["user"], {
#         "name" => :user_name,
#         "email" => :user_email,
#         "id" => :user_id
#       })
#     end
#   end
module FieldExtractor
  extend ActiveSupport::Concern

  private

  # Extract multiple fields from a hash source and assign them to model attributes.
  # Returns early if source is not a Hash.
  #
  # @param source [Hash, nil] The hash containing the fields to extract
  # @param field_mappings [Hash] Mapping of source keys to target attribute names
  #   Example: { "name" => :user_name, "email" => :user_email }
  # @return [void]
  def extract_hash_fields(source, field_mappings)
    return unless source.is_a?(Hash)

    field_mappings.each do |source_key, target_attr|
      # Try both string and symbol keys for flexibility
      value = source[source_key] || source[source_key.to_sym]

      # Handle external_id specially - convert to string if present
      if source_key.to_s.include?("external_id") && value
        value = value.to_s
      end

      self[target_attr] = value if value
    end
  end
end
