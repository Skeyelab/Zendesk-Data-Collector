class ZendeskTicket
  include Mongoid::Document
  include Mongoid::Timestamps

  # Required fields
  field :zendesk_id, type: Integer
  field :domain, type: String

  # Common Zendesk fields
  field :subject, type: String
  field :status, type: String
  field :priority, type: String
  field :ticket_type, type: String
  field :url, type: String

  # Requester fields
  field :req_name, type: String
  field :req_email, type: String
  field :req_id, type: Integer
  field :req_external_id, type: String

  # Assignee fields
  field :assignee_name, type: String
  field :assignee_id, type: Integer
  field :assignee_external_id, type: Integer

  # Group fields
  field :group_name, type: String
  field :group_id, type: Integer

  # Organization fields
  field :organization_name, type: String

  # Time fields
  field :generated_timestamp, type: Integer
  field :created_at, type: Time
  field :updated_at, type: Time
  field :assigned_at, type: Time
  field :initially_assigned_at, type: Time
  field :solved_at, type: Time

  # Time metrics (in minutes)
  field :first_reply_time_in_minutes, type: Integer
  field :first_reply_time_in_minutes_within_business_hours, type: Integer
  field :first_resolution_time_in_minutes, type: Integer
  field :first_resolution_time_in_minutes_within_business_hours, type: Integer
  field :full_resolution_time_in_minutes, type: Integer
  field :full_resolution_time_in_minutes_within_business_hours, type: Integer
  field :agent_wait_time_in_minutes, type: Integer
  field :agent_wait_time_in_minutes_within_business_hours, type: Integer
  field :requester_wait_time_in_minutes, type: Integer
  field :requester_wait_time_in_minutes_within_business_hours, type: Integer
  field :on_hold_time_in_minutes, type: Integer
  field :on_hold_time_in_minutes_within_business_hours, type: Integer

  # Other fields
  field :current_tags, type: String
  field :via, type: String
  field :resolution_time, type: String
  field :satisfaction_score, type: String
  field :group_stations, type: String
  field :assignee_stations, type: String
  field :reopens, type: String
  field :replies, type: String
  field :due_date, type: String

  # Enable dynamic fields for any additional Zendesk API fields
  # This allows storing fields we haven't explicitly defined
  include Mongoid::Attributes::Dynamic

  # Validations
  validates :zendesk_id, presence: true
  validates :domain, presence: true

  # Indexes
  index({ zendesk_id: 1, domain: 1 }, { unique: true })
  index({ zendesk_id: 1 })
  index({ domain: 1 })
  index({ generated_timestamp: 1 })

  # Scopes
  scope :for_domain, ->(domain) { where(domain: domain) }
  scope :recent, -> { order(generated_timestamp: :desc) }
end
