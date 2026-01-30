class CreateIncrementalExportRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :incremental_export_requests do |t|
      t.datetime :requested_at, null: false

      t.timestamps
    end
    add_index :incremental_export_requests, :requested_at
  end
end
