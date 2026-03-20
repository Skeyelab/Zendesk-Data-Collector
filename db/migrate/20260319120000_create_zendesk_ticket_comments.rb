# frozen_string_literal: true

class CreateZendeskTicketComments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :zendesk_ticket_comments do |t|
      t.references :zendesk_ticket, null: false, foreign_key: true, index: false
      t.bigint :zendesk_comment_id, null: false
      t.bigint :author_id
      t.text :body
      t.text :plain_body
      t.boolean :public, default: true
      t.jsonb :via
      t.datetime :created_at, null: false
    end

    add_index :zendesk_ticket_comments, [:zendesk_ticket_id, :zendesk_comment_id],
      unique: true,
      name: :index_ztc_on_ticket_and_comment,
      algorithm: :concurrently
  end
end
