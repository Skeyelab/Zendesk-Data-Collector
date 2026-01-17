source 'https://rubygems.org'

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end

ruby '3.2.4'

# Rails 8
gem 'rails', '~> 8.0'
gem 'dotenv-rails', groups: [:development, :test]

# Database
gem 'pg', '~> 1.5'
gem 'mongoid', '~> 9.0'

# Server
gem 'puma', '~> 6.0'

# Asset pipeline (required for Mission Control - Jobs UI)
gem 'propshaft'

# Background jobs
gem 'solid_queue'
gem 'mission_control-jobs'

# Admin interface
gem 'avo', '~> 3.0'

# Authentication
gem 'devise'

# Zendesk API
gem 'zendesk_api'

# JSON API
gem 'jbuilder', '~> 2.13'

group :development, :test do
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
end

group :development do
  gem 'pry-rails'
  gem 'seed_dump'
  gem 'foreman'
end

group :test do
  gem 'rspec-rails'
  gem 'simplecov', require: false
  gem 'webmock'
  gem 'mongoid-rspec'
  gem 'capybara'
  gem 'selenium-webdriver'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
