class OptimizeZendeskTicketsIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Drop 1 GB GIN index — never used; raw_data is read as a blob, not searched
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_raw_data,
      algorithm: :concurrently, if_exists: true

    # Drop indexes with zero scans that are never queried
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_zendesk_id,
      algorithm: :concurrently, if_exists: true                                    # redundant with (zendesk_id, domain) unique
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_requester_updated_at,
      algorithm: :concurrently, if_exists: true
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_custom_status_updated_at,
      algorithm: :concurrently, if_exists: true
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_latest_comment_added_at,
      algorithm: :concurrently, if_exists: true
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_solved_at,
      algorithm: :concurrently, if_exists: true
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_assignee_updated_at,
      algorithm: :concurrently, if_exists: true
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_status_updated_at,
      algorithm: :concurrently, if_exists: true
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_generated_timestamp,
      algorithm: :concurrently, if_exists: true
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_assignee_id,
      algorithm: :concurrently, if_exists: true                                    # noctua queries raw_data->>'assignee_id', not this column
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_domain,
      algorithm: :concurrently, if_exists: true                                    # domain always paired with status
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_group_id,
      algorithm: :concurrently, if_exists: true                                    # never queried
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_due_at,
      algorithm: :concurrently, if_exists: true                                    # never queried

    # Add composite indexes matching actual query patterns
    # Nearly every query: WHERE domain = ? AND status (NOT) IN (...)  ORDER BY created_at
    add_index :zendesk_tickets, [:domain, :status, :created_at],
      name: :index_zendesk_tickets_on_domain_status_created_at,
      algorithm: :concurrently

    # Requester analysis queries: WHERE domain = ? AND req_id = ?
    add_index :zendesk_tickets, [:domain, :req_id],
      name: :index_zendesk_tickets_on_domain_req_id,
      algorithm: :concurrently
  end

  def down
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_domain_status_created_at,
      algorithm: :concurrently, if_exists: true
    remove_index :zendesk_tickets, name: :index_zendesk_tickets_on_domain_req_id,
      algorithm: :concurrently, if_exists: true

    # Only restore indexes for columns that exist in the current schema
    add_index :zendesk_tickets, :raw_data, using: :gin,
      name: :index_zendesk_tickets_on_raw_data, algorithm: :concurrently
    add_index :zendesk_tickets, :zendesk_id,
      name: :index_zendesk_tickets_on_zendesk_id, algorithm: :concurrently
    add_index :zendesk_tickets, :solved_at,
      name: :index_zendesk_tickets_on_solved_at, algorithm: :concurrently
    add_index :zendesk_tickets, :generated_timestamp,
      name: :index_zendesk_tickets_on_generated_timestamp, algorithm: :concurrently
    add_index :zendesk_tickets, :assignee_id,
      name: :index_zendesk_tickets_on_assignee_id, algorithm: :concurrently
    add_index :zendesk_tickets, :domain,
      name: :index_zendesk_tickets_on_domain, algorithm: :concurrently
    add_index :zendesk_tickets, :group_id,
      name: :index_zendesk_tickets_on_group_id, algorithm: :concurrently
    # Note: requester_updated_at, custom_status_updated_at, latest_comment_added_at,
    # assignee_updated_at, status_updated_at, due_at columns no longer exist in schema
  end
end
