class DropActiveAdminComments < ActiveRecord::Migration[8.0]
  def up
    # Safely drop table if it exists
    # This migration is idempotent - safe to run multiple times
    if connection.table_exists?(:active_admin_comments)
      drop_table :active_admin_comments
    else
      puts "Table 'active_admin_comments' does not exist, skipping drop"
    end
  end

  def down
    # Recreate table for rollback (if needed)
    unless connection.table_exists?(:active_admin_comments)
      create_table :active_admin_comments do |t|
        t.string :namespace
        t.text :body
        t.string :resource_id, null: false
        t.string :resource_type, null: false
        t.references :author, polymorphic: true
        t.timestamps
      end
      add_index :active_admin_comments, [:namespace]
      add_index :active_admin_comments, [:resource_type, :resource_id]
    end
  end
end
