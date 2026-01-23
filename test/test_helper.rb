ENV["RAILS_ENV"] ||= "test"

require "simplecov"

SimpleCov.start "rails" do
  enable_coverage :branch
  add_filter "/test/"
  add_filter "/config/"
  # Filter out unused skeleton files that Rails generates
  add_filter "/app/channels/"  # ActionCable not used
  add_filter "/app/mailers/application_mailer.rb"  # No emails sent
  add_filter "/app/controllers/avo/desk_resources_controller.rb"  # Empty routing shim
end
require_relative "../config/environment"
require "rails/test_help"
require "capybara/rails"
require "capybara/minitest"

# Note: Avo base classes (MetricCard, ChartkickCard, BaseDashboard) are only available
# when the Avo engine is fully initialized at runtime. In tests, we skip loading
# our custom Avo classes to avoid NameError. The classes will work correctly
# when the application runs normally.

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
  setup do
    ActiveJob::Base.queue_adapter = :test
    ZendeskTicket.destroy_all if defined?(ZendeskTicket)
  end
end

class ActionDispatch::IntegrationTest
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include Devise::Test::IntegrationHelpers

  def teardown
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  def sign_in(user)
    visit new_admin_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
  end
end
