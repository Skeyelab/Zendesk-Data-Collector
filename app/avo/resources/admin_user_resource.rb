class Avo::Resources::AdminUserResource < Avo::BaseResource
  self.model_class = AdminUser
  self.title = :email
  self.includes = []

  def fields
    field :id, as: :id
    field :email, as: :text, required: true
    field :password, as: :password, placeholder: "Leave blank to keep unchanged"
    field :created_at, as: :date_time, readonly: true
    field :updated_at, as: :date_time, readonly: true
    field :sign_in_count, as: :number, readonly: true
    field :current_sign_in_at, as: :date_time, readonly: true
    field :last_sign_in_at, as: :date_time, readonly: true
  end
end
