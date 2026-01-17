class DropActiveAdminComments < ActiveRecord::Migration[8.0]
  def up
    # Use raw SQL to safely drop table if it exists
    # CASCADE ensures any dependent objects are also dropped
    # IF EXISTS makes this safe to run even if the table doesn't exist
    execute "DROP TABLE IF EXISTS active_admin_comments CASCADE"
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
