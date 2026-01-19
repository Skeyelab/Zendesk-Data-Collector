class CreateZendeskTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :zendesk_tickets do |t|
      # Required fields
      t.integer :zendesk_id, null: false
      t.string :domain, null: false

      # Common Zendesk fields
      t.string :subject
      t.string :status
      t.string :priority
      t.string :ticket_type
      t.string :url

      # Requester fields
      t.string :req_name
      t.string :req_email
      t.bigint :req_id
      t.string :req_external_id

      # Assignee fields
      t.string :assignee_name
      t.bigint :assignee_id
      t.bigint :assignee_external_id

      # Group fields
      t.string :group_name
      t.bigint :group_id

      # Organization fields
      t.string :organization_name

      # Time fields
      t.integer :generated_timestamp
      t.datetime :assigned_at
      t.datetime :initially_assigned_at
      t.datetime :solved_at

      # Time metrics (in minutes)
      t.integer :first_reply_time_in_minutes
      t.integer :first_reply_time_in_minutes_within_business_hours
      t.integer :first_resolution_time_in_minutes
      t.integer :first_resolution_time_in_minutes_within_business_hours
      t.integer :full_resolution_time_in_minutes
      t.integer :full_resolution_time_in_minutes_within_business_hours
      t.integer :agent_wait_time_in_minutes
      t.integer :agent_wait_time_in_minutes_within_business_hours
      t.integer :requester_wait_time_in_minutes
      t.integer :requester_wait_time_in_minutes_within_business_hours
      t.integer :on_hold_time_in_minutes
      t.integer :on_hold_time_in_minutes_within_business_hours

      # Other fields
      t.text :current_tags
      t.string :via
      t.string :resolution_time
      t.string :satisfaction_score
      t.string :group_stations
      t.string :assignee_stations
      t.string :reopens
      t.string :replies
      t.string :due_date

      # JSONB column for complete API response and dynamic fields
      t.jsonb :raw_data, default: {}

      # Timestamps
      t.timestamps
    end

    # Indexes for common queries
    add_index :zendesk_tickets, [:zendesk_id, :domain], unique: true
    add_index :zendesk_tickets, :zendesk_id
    add_index :zendesk_tickets, :domain
    add_index :zendesk_tickets, :generated_timestamp
    add_index :zendesk_tickets, :status
    add_index :zendesk_tickets, :created_at
    add_index :zendesk_tickets, :updated_at
    add_index :zendesk_tickets, :solved_at
    add_index :zendesk_tickets, :group_id
    add_index :zendesk_tickets, :assignee_id

    # GIN index on JSONB for fast queries on any field in raw_data
    add_index :zendesk_tickets, :raw_data, using: :gin
  end
end
