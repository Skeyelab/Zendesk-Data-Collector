web: PORT=3000 bundle exec puma -t 5:5 -p 3000 -e ${RACK_ENV:-development}
worker1: bundle exec bin/jobs start
#worker2: bundle exec bin/jobs start
#clock: bundle exec clockwork config/clockwork.rb
