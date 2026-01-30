class AddFetchFlagsToDesks < ActiveRecord::Migration[8.1]
  def change
    add_column :desks, :fetch_comments, :boolean, default: true, null: false
    add_column :desks, :fetch_metrics, :boolean, default: true, null: false
  end
end
