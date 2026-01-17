class DropActiveAdminComments < ActiveRecord::Migration[8.0]
  def change
    # Safely drop table if it exists
    # This migration is idempotent - safe to run multiple times
    drop_table :active_admin_comments, if_exists: true
  end
end
