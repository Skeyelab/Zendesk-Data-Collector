# frozen_string_literal: true

class DropGeetsZendeskCom < ActiveRecord::Migration[8.0]
  def up
    drop_table :geets_zendesk_com, if_exists: true
  end

  def down
    # Table was legacy; no recreation.
  end
end
