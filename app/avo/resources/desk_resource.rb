class Avo::Resources::DeskResource < Avo::BaseResource
  self.model_class = Desk
  self.title = :domain
  self.includes = []

  def fields
    field :id, as: :id
    field :domain, as: :text, required: true
    field :user, as: :text, required: true
    field :token, as: :password, required: true, placeholder: "Enter Zendesk API token"
    field :active, as: :boolean
    field :queued, as: :boolean, readonly: true
    field :fetch_comments, as: :boolean, help: "Enable fetching ticket comments for this desk"
    field :fetch_metrics, as: :boolean, help: "Enable fetching ticket metrics for this desk"
    field :last_timestamp, as: :number, readonly: false
    field :last_timestamp_event, as: :number, readonly: true
    field :wait_till, as: :number, readonly: true
    field :wait_till_event, as: :number, readonly: true
    field :created_at, as: :date_time, readonly: true
    field :updated_at, as: :date_time, readonly: true
  end
end
