class AddQueuedToDesks < ActiveRecord::Migration[5.0]
  def change
    add_column :desks, :queued, :boolean
  end
end
