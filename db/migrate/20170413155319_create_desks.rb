class CreateDesks < ActiveRecord::Migration[5.0]
  def change
    create_table :desks do |t|
      t.string :domain
      t.string :user
      t.string :encrypted_token
      t.string :encrypted_token_iv
      t.integer :last_timestamp
      t.integer :last_timestamp_event
      t.integer :wait_till
      t.integer :wait_till_event
      t.boolean :active

      t.timestamps
    end
    add_index :desks, :domain, unique: true
  end
end
