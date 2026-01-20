class Avo::Resources::ZendeskTicketResource < Avo::BaseResource
  self.model_class = ZendeskTicket
  self.title = :subject
  self.includes = []

  def default_sort
    {
      updated_at: :desc
    }
  end

  def fields
    field :id, as: :id
    field :zendesk_id, as: :number, required: true, sortable: true
    field :domain, as: :text, required: true, sortable: true
    field :subject, as: :text, sortable: true
    field :status, as: :select, options: {
      new: "new",
      open: "open",
      pending: "pending",
      solved: "solved",
      closed: "closed"
    }, sortable: true
    field :priority, as: :select, options: {
      urgent: "urgent",
      high: "high",
      normal: "normal",
      low: "low"
    }, sortable: true
    field :ticket_type, as: :text, sortable: true
    field :url, as: :text

    # Requester fields
    field :req_name, as: :text, sortable: true
    field :req_email, as: :text, sortable: true
    field :req_id, as: :number, sortable: true
    field :req_external_id, as: :text

    # Assignee fields
    field :assignee_name, as: :text, sortable: true
    field :assignee_id, as: :number, sortable: true
    field :assignee_external_id, as: :number

    # Group fields
    field :group_name, as: :text, sortable: true
    field :group_id, as: :number, sortable: true

    # Organization fields
    field :organization_name, as: :text, sortable: true

    # Time fields
    field :generated_timestamp, as: :number, readonly: true, sortable: true
    field :created_at, as: :date_time, readonly: true, sortable: true
    field :updated_at, as: :date_time, readonly: true, sortable: true
    field :assigned_at, as: :date_time, readonly: true, sortable: true
    field :initially_assigned_at, as: :date_time, readonly: true, sortable: true
    field :solved_at, as: :date_time, readonly: true, sortable: true

    # Time metrics
    field :first_reply_time_in_minutes, as: :number, readonly: true, sortable: true
    field :first_resolution_time_in_minutes, as: :number, readonly: true, sortable: true
    field :full_resolution_time_in_minutes, as: :number, readonly: true, sortable: true

    # Other fields
    field :current_tags, as: :text
    field :via, as: :text
    field :satisfaction_score, as: :text, sortable: true

    # JSONB raw_data - show as JSON viewer for complete API response
    field :raw_data, as: :code, readonly: true, language: :json
  end
end
