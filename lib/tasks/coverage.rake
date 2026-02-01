# frozen_string_literal: true

# Merge coverage from parallel test workers into a single report.
# Required for accurate coverage when using parallelize(workers: ...) in test_helper.
namespace :coverage do
  desc "Merge worker coverage results into coverage/"
  task :merge do
    require "simplecov"

    files = Dir["coverage/worker_*/.resultset*.json"]
    if files.empty?
      warn "No worker coverage found (coverage/worker_*/.resultset*.json). Run tests first."
      next
    end

    SimpleCov.collate files, "rails" do
      enable_coverage :branch
      add_filter "/test/"
      add_filter "/config/"
      add_filter "/app/channels/"
      add_filter "/app/mailers/application_mailer.rb"
      add_filter "/app/controllers/avo/desk_resources_controller.rb"
    end
  end
end
