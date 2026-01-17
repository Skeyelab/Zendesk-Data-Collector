# Configure Mission Control - Jobs to use Devise authentication instead of HTTP Basic Auth
# We're using Devise authentication via the authenticate block in routes.rb
MissionControl::Jobs.http_basic_auth_enabled = false
MissionControl::Jobs.base_controller_class = "MissionControl::BaseController"
