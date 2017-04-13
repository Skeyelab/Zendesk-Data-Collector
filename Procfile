web: bundle exec puma -t 5:5 -p ${PORT:-3000} -e ${RACK_ENV:-development}
worker: bundle exec sidekiq -e ${RAILS_ENV:-development} -C config/sidekiq.yml
#clock: bundle exec clockwork config/clockwork.rb