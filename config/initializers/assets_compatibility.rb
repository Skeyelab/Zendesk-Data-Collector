# Rails 8 compatibility shim for gems that still expect assets configuration
# This provides a minimal assets config object for gems like avo-icons that haven't been updated yet

if Rails.application.config.respond_to?(:assets)
  # Assets already configured (shouldn't happen in Rails 8, but just in case)
else
  # Create a minimal compatibility shim
  module Rails
    class Application
      class Configuration
        def assets
          @assets ||= ActiveSupport::OrderedOptions.new.tap do |assets|
            assets.enabled = false
            assets.paths = []
            assets.precompile = []
            assets.version = '1.0'
            assets.prefix = '/assets'
          end
        end
      end
    end
  end
end

# Add assets_manifest method to Rails.application for compatibility
module Rails
  class Application
    def assets_manifest
      @assets_manifest ||= OpenStruct.new(
        find_asset: ->(path) { nil },
        assets: {}
      )
    end
  end
end

# Configure inline_svg to use file system strategy instead of asset pipeline
# This is needed for Rails 8 which removed the asset pipeline
if defined?(InlineSvg)
  InlineSvg.configure do |config|
    config.asset_finder = InlineSvg::StaticAssetFinder.new(
      paths: [
        Rails.root.join('app', 'assets', 'images'),
        Rails.root.join('vendor', 'assets', 'images'),
        # Add gem paths for avo-icons
        *Dir.glob(Rails.root.join('vendor', 'gems', '**', 'app', 'assets', 'images')),
      ]
    )
  end
end
