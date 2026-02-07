require "test_helper"

class FieldExtractorTest < ActiveSupport::TestCase
  # Create a test model class that includes FieldExtractor
  class TestModel
    include ActiveModel::Model
    include FieldExtractor

    attr_accessor :user_name, :user_email, :user_id, :user_external_id,
      :org_name, :org_id

    def [](attribute)
      send(attribute)
    end

    def []=(attribute, value)
      send("#{attribute}=", value)
    end
  end

  def setup
    @model = TestModel.new
  end

  test "should extract fields from hash with string keys" do
    user_data = {
      "name" => "John Doe",
      "email" => "john@example.com",
      "id" => 123
    }

    @model.send(:extract_hash_fields, user_data, {
      "name" => :user_name,
      "email" => :user_email,
      "id" => :user_id
    })

    assert_equal "John Doe", @model.user_name
    assert_equal "john@example.com", @model.user_email
    assert_equal 123, @model.user_id
  end

  test "should extract fields from hash with symbol keys" do
    user_data = {
      name: "Jane Smith",
      email: "jane@example.com",
      id: 456
    }

    @model.send(:extract_hash_fields, user_data, {
      "name" => :user_name,
      "email" => :user_email,
      "id" => :user_id
    })

    assert_equal "Jane Smith", @model.user_name
    assert_equal "jane@example.com", @model.user_email
    assert_equal 456, @model.user_id
  end

  test "should convert external_id to string" do
    user_data = {
      "external_id" => 789
    }

    @model.send(:extract_hash_fields, user_data, {
      "external_id" => :user_external_id
    })

    assert_equal "789", @model.user_external_id
    assert_instance_of String, @model.user_external_id
  end

  test "should handle nil source gracefully" do
    assert_nothing_raised do
      @model.send(:extract_hash_fields, nil, {
        "name" => :user_name,
        "email" => :user_email
      })
    end

    assert_nil @model.user_name
    assert_nil @model.user_email
  end

  test "should handle non-hash source gracefully" do
    assert_nothing_raised do
      @model.send(:extract_hash_fields, "not a hash", {
        "name" => :user_name,
        "email" => :user_email
      })
    end

    assert_nil @model.user_name
    assert_nil @model.user_email
  end

  test "should skip nil values" do
    user_data = {
      "name" => "Test User",
      "email" => nil,
      "id" => 999
    }

    @model.send(:extract_hash_fields, user_data, {
      "name" => :user_name,
      "email" => :user_email,
      "id" => :user_id
    })

    assert_equal "Test User", @model.user_name
    assert_nil @model.user_email
    assert_equal 999, @model.user_id
  end

  test "should handle mixed string and symbol keys in source" do
    user_data = {
      "name" => "Mixed Keys",
      :email => "mixed@example.com",
      "id" => 111
    }

    @model.send(:extract_hash_fields, user_data, {
      "name" => :user_name,
      "email" => :user_email,
      "id" => :user_id
    })

    assert_equal "Mixed Keys", @model.user_name
    assert_equal "mixed@example.com", @model.user_email
    assert_equal 111, @model.user_id
  end

  test "should work with ZendeskTicket model for real integration" do
    ticket = ZendeskTicket.new

    requester_data = {
      "name" => "Real User",
      "email" => "real@example.com",
      "id" => 555,
      "external_id" => 777
    }

    ticket.send(:extract_requester_fields, requester_data)

    assert_equal "Real User", ticket.req_name
    assert_equal "real@example.com", ticket.req_email
    assert_equal 555, ticket.req_id
    assert_equal "777", ticket.req_external_id
  end

  test "should handle empty hash" do
    @model.send(:extract_hash_fields, {}, {
      "name" => :user_name,
      "email" => :user_email
    })

    assert_nil @model.user_name
    assert_nil @model.user_email
  end

  test "should only extract specified fields" do
    user_data = {
      "name" => "Selective User",
      "email" => "selective@example.com",
      "id" => 888,
      "unspecified_field" => "should not be extracted"
    }

    @model.send(:extract_hash_fields, user_data, {
      "name" => :user_name,
      "id" => :user_id
      # Note: email is not in the mapping
    })

    assert_equal "Selective User", @model.user_name
    assert_equal 888, @model.user_id
    assert_nil @model.user_email
  end
end
