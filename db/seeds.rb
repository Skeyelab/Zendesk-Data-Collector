# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)
if ENV['DEFAULT_ADMIN_USER'] && ENV['DEFAULT_ADMIN_PW']
  AdminUser.find_or_create_by!(email: ENV['DEFAULT_ADMIN_USER']) do |user|
    user.password = ENV['DEFAULT_ADMIN_PW']
    user.password_confirmation = ENV['DEFAULT_ADMIN_PW']
  end
else
  puts "Skipping AdminUser creation - set DEFAULT_ADMIN_USER and DEFAULT_ADMIN_PW in .env to create an admin user"
end
