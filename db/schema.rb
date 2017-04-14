# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20170414195919) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_admin_comments", force: :cascade do |t|
    t.string   "namespace"
    t.text     "body"
    t.string   "resource_id",   null: false
    t.string   "resource_type", null: false
    t.string   "author_type"
    t.integer  "author_id"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author_type_and_author_id", using: :btree
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace", using: :btree
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource_type_and_resource_id", using: :btree
  end

  create_table "admin_users", force: :cascade do |t|
    t.string   "email",                  default: "", null: false
    t.string   "encrypted_password",     default: "", null: false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          default: 0,  null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.inet     "current_sign_in_ip"
    t.inet     "last_sign_in_ip"
    t.datetime "created_at",                          null: false
    t.datetime "updated_at",                          null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true, using: :btree
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true, using: :btree
  end

  create_table "desks", force: :cascade do |t|
    t.string   "domain"
    t.string   "user"
    t.string   "encrypted_token"
    t.string   "encrypted_token_iv"
    t.integer  "last_timestamp"
    t.integer  "last_timestamp_event"
    t.integer  "wait_till"
    t.integer  "wait_till_event"
    t.boolean  "active"
    t.datetime "created_at",           null: false
    t.datetime "updated_at",           null: false
    t.boolean  "queued"
    t.index ["domain"], name: "index_desks_on_domain", unique: true, using: :btree
  end

  create_table "geets_zendesk_com", id: :integer, force: :cascade do |t|
    t.integer  "generated_timestamp"
    t.string   "req_name",                                               limit: 64
    t.bigint   "req_id"
    t.string   "req_external_id",                                        limit: 64
    t.string   "req_email",                                              limit: 255
    t.string   "domain",                                                 limit: 255
    t.string   "submitter_name",                                         limit: 64
    t.string   "assignee_name",                                          limit: 64
    t.string   "group_name",                                             limit: 64
    t.string   "subject",                                                limit: 255
    t.string   "current_tags",                                           limit: 1024
    t.string   "status",                                                 limit: 255
    t.string   "priority",                                               limit: 255
    t.string   "via",                                                    limit: 255
    t.string   "ticket_type",                                            limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "assigned_at"
    t.string   "organization_name",                                      limit: 64
    t.string   "due_date",                                               limit: 255
    t.datetime "initially_assigned_at"
    t.datetime "solved_at"
    t.string   "resolution_time",                                        limit: 255
    t.string   "satisfaction_score",                                     limit: 255
    t.string   "group_stations",                                         limit: 255
    t.string   "assignee_stations",                                      limit: 255
    t.string   "reopens",                                                limit: 255
    t.string   "replies",                                                limit: 255
    t.integer  "first_reply_time_in_minutes"
    t.integer  "first_reply_time_in_minutes_within_business_hours"
    t.integer  "first_resolution_time_in_minutes"
    t.integer  "first_resolution_time_in_minutes_within_business_hours"
    t.integer  "full_resolution_time_in_minutes"
    t.integer  "full_resolution_time_in_minutes_within_business_hours"
    t.integer  "agent_wait_time_in_minutes"
    t.integer  "agent_wait_time_in_minutes_within_business_hours"
    t.integer  "requester_wait_time_in_minutes"
    t.integer  "requester_wait_time_in_minutes_within_business_hours"
    t.integer  "on_hold_time_in_minutes"
    t.integer  "on_hold_time_in_minutes_within_business_hours"
    t.bigint   "assignee_id"
    t.bigint   "assignee_external_id"
    t.bigint   "group_id"
    t.string   "field_76108047",                                         limit: 255
    t.string   "url",                                                    limit: 255
  end

end
