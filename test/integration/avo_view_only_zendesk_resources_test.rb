# frozen_string_literal: true

require "test_helper"

class AvoViewOnlyZendeskResourcesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = AdminUser.create!(
      email: "avo-view-only@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    sign_in @admin, scope: :admin_user
  end

  test "POST create on ticket resource returns forbidden" do
    post avo.resources_zendesk_ticket_resources_path
    assert_response :forbidden
  end

  test "GET new on ticket resource returns forbidden" do
    get avo.new_resources_zendesk_ticket_resource_path
    assert_response :forbidden
  end

  test "POST create on comment resource returns forbidden" do
    post avo.resources_zendesk_ticket_comment_resources_path
    assert_response :forbidden
  end

  test "GET new on comment resource returns forbidden" do
    get avo.new_resources_zendesk_ticket_comment_resource_path
    assert_response :forbidden
  end
end
