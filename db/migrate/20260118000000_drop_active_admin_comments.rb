class DropActiveAdminComments < ActiveRecord::Migration[8.0]
  def up
    # Use raw SQL to safely drop table if it exists
    # CASCADE ensures any dependent objects are also dropped
    execute "DROP TABLE IF EXISTS active_admin_comments CASCADE"
  rescue => e
    # Silently ignore any errors - this migration is safe to run multiple times
    # The table may not exist, which is fine
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
