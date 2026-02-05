source "https://rubygems.org"

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end

ruby "3.2.3"

# Rails 8
gem "dotenv-rails", groups: %i[development test]
gem "rails", "~> 8.0"

# Database
gem "pg", "~> 1.5"

# Server
gem "puma", "~> 6.0"

# Asset pipeline (required for Mission Control - Jobs UI)
gem "propshaft"

# Background jobs
gem "mission_control-jobs"
gem "solid_queue"

# Admin interface
gem "avo", "~> 3.0"
gem "chartkick"
gem "ransack"

# Authentication
gem "devise"

# Rate limiting
gem "rack-attack"

# Zendesk API
gem "zendesk_api"

# JSON API
gem "jbuilder", "~> 2.13"

group :development, :test do
  gem "byebug", platforms: %i[mri mingw x64_mingw]
end

group :development do
  gem "foreman"
  gem "pry-rails"
  gem "seed_dump"
  gem "standard"
end

group :test do
  gem "capybara"
  gem "rspec-rails"
  gem "selenium-webdriver"
  gem "simplecov", require: false
  gem "webmock"
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[mingw mswin x64_mingw jruby]
