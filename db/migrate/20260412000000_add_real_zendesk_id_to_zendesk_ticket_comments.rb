# frozen_string_literal: true

class AddRealZendeskIdToZendeskTicketComments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :zendesk_ticket_comments, :real_zendesk_id, :bigint

    add_index :zendesk_ticket_comments, :real_zendesk_id,
      name: :index_ztc_on_real_zendesk_id,
      algorithm: :concurrently
  end

  def down
    remove_index :zendesk_ticket_comments, name: :index_ztc_on_real_zendesk_id, if_exists: true
    remove_column :zendesk_ticket_comments, :real_zendesk_id
  end
end
