ActiveAdmin.register Desk do
  permit_params :domain, :user, :token, :active ## Add this line

  show do
    #panel "Desk"
    attributes_table do
      row :domain
      row :user
      row :token
      row :active
    end
  end

  form do |f|
    inputs "Details" do
      input :domain
      input :user
      input :token
      input :active

    end
    para "Press cancel to return to the list without saving."
    actions
  end
end






# See permitted parameters documentation:
# https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
#
# permit_params :list, :of, :attributes, :on, :model
#
# or
#
# permit_params do
#   permitted = [:permitted, :attributes]
#   permitted << :other if params[:action] == 'create' && current_user.admin?
#   permitted
# end
