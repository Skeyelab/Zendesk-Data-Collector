class Avo::Resources::ZendeskTicketResource < Avo::BaseResource
  self.model_class = ZendeskTicket
  self.title = :subject
  self.includes = []

  def fields
    field :id, as: :id
    field :zendesk_id, as: :number, required: true
    field :domain, as: :text, required: true
    field :subject, as: :text
    field :status, as: :select, options: {
      open: "open",
      pending: "pending",
      solved: "solved",
      closed: "closed"
    }
    field :priority, as: :select, options: {
      urgent: "urgent",
      high: "high",
      normal: "normal",
      low: "low"
    }
    field :ticket_type, as: :text
    field :url, as: :text
    
    # Requester fields
    field :req_name, as: :text
    field :req_email, as: :text
    field :req_id, as: :number
    field :req_external_id, as: :text
    
    # Assignee fields
    field :assignee_name, as: :text
    field :assignee_id, as: :number
    field :assignee_external_id, as: :number
    
    # Group fields
    field :group_name, as: :text
    field :group_id, as: :number
    
    # Organization fields
    field :organization_name, as: :text
    
    # Time fields
    field :generated_timestamp, as: :number, readonly: true
    field :created_at, as: :date_time, readonly: true
    field :updated_at, as: :date_time, readonly: true
    field :assigned_at, as: :date_time, readonly: true
    field :initially_assigned_at, as: :date_time, readonly: true
    field :solved_at, as: :date_time, readonly: true
    
    # Time metrics
    field :first_reply_time_in_minutes, as: :number, readonly: true
    field :first_resolution_time_in_minutes, as: :number, readonly: true
    field :full_resolution_time_in_minutes, as: :number, readonly: true
    
    # Other fields
    field :current_tags, as: :text
    field :via, as: :text
    field :satisfaction_score, as: :text
    
    # JSONB raw_data - show as JSON viewer for complete API response
    field :raw_data, as: :code, readonly: true, language: :json
  end
end
