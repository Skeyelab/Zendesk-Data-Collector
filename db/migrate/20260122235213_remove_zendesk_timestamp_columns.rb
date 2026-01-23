class RemoveZendeskTimestampColumns < ActiveRecord::Migration[8.1]
  def change
    remove_index :zendesk_tickets, :zendesk_created_at, if_exists: true
    remove_index :zendesk_tickets, :zendesk_updated_at, if_exists: true

    remove_column :zendesk_tickets, :zendesk_created_at, :datetime
    remove_column :zendesk_tickets, :zendesk_updated_at, :datetime
  end
end
