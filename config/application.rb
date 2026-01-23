require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ZDDatacollector
  class Application < Rails::Application
    config.load_defaults 8.0

    # Use Solid Queue for background jobs
    config.active_job.queue_adapter = :solid_queue

    # Enable Rack::Attack middleware
    config.middleware.use Rack::Attack

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.
  end
end
