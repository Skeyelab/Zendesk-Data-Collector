# frozen_string_literal: true

class AddRealZendeskIdToZendeskTicketComments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :zendesk_ticket_comments, :real_zendesk_id, :bigint

    # Backfill from the parent zendesk_tickets table
    execute <<~SQL
      UPDATE zendesk_ticket_comments c
      SET real_zendesk_id = t.zendesk_id
      FROM zendesk_tickets t
      WHERE c.zendesk_ticket_id = t.id
    SQL

    add_index :zendesk_ticket_comments, :real_zendesk_id,
      name: :index_ztc_on_real_zendesk_id,
      algorithm: :concurrently
  end

  def down
    remove_index :zendesk_ticket_comments, name: :index_ztc_on_real_zendesk_id
    remove_column :zendesk_ticket_comments, :real_zendesk_id
  end
end
