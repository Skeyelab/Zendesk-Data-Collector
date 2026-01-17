# Patch Avo's dynamic routes to use ResourcesController for all resources
# This fixes the issue where Avo generates routes like `resources :admin_user_resources`
# which Rails expects to have a controller `Avo::AdminUserResourcesController`,
# but Avo only provides `Avo::ResourcesController`.

# Override the method directly
module Avo
  module Routes
    module DynamicRoutes
      def self.draw(router)
        Avo::Resources::ResourceManager.fetch_resources.map do |resource|
          router.resources resource.route_key, controller: 'resources', param: :id do
            router.member do
              router.get :preview
            end
          end
        end
      end
    end
  end
end
