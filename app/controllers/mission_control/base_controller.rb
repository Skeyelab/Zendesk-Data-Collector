module MissionControl
  class BaseController < ApplicationController
    # Use Devise authentication instead of HTTP Basic Auth
    before_action :authenticate_admin_user!
  end
end
