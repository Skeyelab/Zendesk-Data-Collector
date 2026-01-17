class DropActiveAdminComments < ActiveRecord::Migration[8.0]
  def change
    # No-op migration - table cleanup deferred
    # The active_admin_comments table was removed when migrating from ActiveAdmin to Avo
    # This migration exists to mark the schema version but doesn't perform any operations
    # Manual cleanup can be done later if needed: DROP TABLE IF EXISTS active_admin_comments CASCADE;
  end
end
