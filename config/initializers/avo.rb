Avo.configure do |config|
  config.app_name = "Zendesk Data Collector"
  config.timezone = "UTC"
  config.currency = "USD"
  config.per_page = 24
  config.per_page_steps = [12, 24, 48, 72]
  config.via_per_page = 8
  config.default_view_type = :table
  config.id_links_to_resource = true
  config.full_width_container = false
  config.full_width_index_view = false
  config.cache_resources_on_index_view = true
  config.search_debounce = 300
  config.view_component_path = "app/components"
  config.display_breadcrumbs = true
  config.set_initial_breadcrumbs do
    add_breadcrumb "Home", "/avo"
  end

  # Authentication
  config.current_user_method = :current_admin_user
  config.authenticate_with do
    redirect_to new_admin_user_session_path unless admin_user_signed_in?
  end
  config.sign_out_path_name = :destroy_admin_user_session_path
  config.root_path = "/avo"
end
