class DropActiveAdminComments < ActiveRecord::Migration[8.0]
  def up
    # Use raw SQL to safely drop table if it exists
    execute "DROP TABLE IF EXISTS active_admin_comments CASCADE" if connection.table_exists?(:active_admin_comments)
  rescue => e
    # Silently ignore if table doesn't exist or any other error
    # This migration is safe to run multiple times
    Rails.logger.warn("Could not drop active_admin_comments table: #{e.message}") if defined?(Rails)
  end

  def down
    return if connection.table_exists?(:active_admin_comments)
    
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
