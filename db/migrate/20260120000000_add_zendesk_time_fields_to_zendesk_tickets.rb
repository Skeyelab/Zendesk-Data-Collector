class AddZendeskTimeFieldsToZendeskTickets < ActiveRecord::Migration[8.1]
  def change
    # Fix: Store Zendesk timestamps separately from Rails timestamps
    add_column :zendesk_tickets, :zendesk_created_at, :datetime
    add_column :zendesk_tickets, :zendesk_updated_at, :datetime
    
    # Add missing Ticket Metrics time fields
    add_column :zendesk_tickets, :status_updated_at, :datetime
    add_column :zendesk_tickets, :latest_comment_added_at, :datetime
    add_column :zendesk_tickets, :requester_updated_at, :datetime
    add_column :zendesk_tickets, :assignee_updated_at, :datetime
    add_column :zendesk_tickets, :custom_status_updated_at, :datetime
    
    # Convert due_date from string to datetime
    add_column :zendesk_tickets, :due_at, :datetime
    # We'll keep due_date as string for backward compatibility, but prefer due_at
    
    add_index :zendesk_tickets, :zendesk_created_at
    add_index :zendesk_tickets, :zendesk_updated_at
    add_index :zendesk_tickets, :status_updated_at
    add_index :zendesk_tickets, :latest_comment_added_at
    add_index :zendesk_tickets, :requester_updated_at
    add_index :zendesk_tickets, :assignee_updated_at
    add_index :zendesk_tickets, :custom_status_updated_at
    add_index :zendesk_tickets, :due_at
  end
end
