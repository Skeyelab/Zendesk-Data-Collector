class AddTokenToDesks < ActiveRecord::Migration::Current
  def change
    add_column :desks, :token, :text
    remove_column :desks, :encrypted_token, :string
    remove_column :desks, :encrypted_token_iv, :string
  end
end
