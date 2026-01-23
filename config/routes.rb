Rails.application.routes.draw do
  devise_for :admin_users

  authenticate :admin_user do
    mount Avo::Engine, at: Avo.configuration.root_path
    mount MissionControl::Jobs::Engine, at: "/jobs"
    get "/dashboard", to: "dashboard#index", as: :dashboard
  end

  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  root to: redirect(Avo.configuration.root_path)
end
