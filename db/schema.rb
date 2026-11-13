# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_11_190000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "customers", force: :cascade do |t|
    t.string "email", null: false
    t.datetime "email_verified_at"
    t.string "sign_in_code_digest"
    t.datetime "sign_in_code_expires_at"
    t.integer "sign_in_code_attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_customers_on_email", unique: true
  end

  create_table "events", force: :cascade do |t|
    t.bigint "venue_id", null: false
    t.string "name", null: false
    t.datetime "start_time", null: false
    t.datetime "end_time", null: false
    t.jsonb "layout_snapshot", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ticket_price_cents", null: false
    t.index ["venue_id"], name: "index_events_on_venue_id"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "reservation_id", null: false
    t.string "external_id", null: false
    t.string "status", null: false
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider_key", null: false
    t.string "currency", null: false
    t.string "failure_code"
    t.index ["external_id"], name: "index_payments_on_external_id", unique: true
    t.index ["reservation_id"], name: "index_payments_on_reservation_id"
    t.index ["reservation_id"],
            name: "index_payments_one_pending_per_reservation",
            unique: true,
            where: "((status)::text = 'pending'::text)"
  end

  create_table "reservations", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "customer_id", null: false
    t.integer "row_id", null: false
    t.int4range "seat_range", null: false
    t.string "status", default: "held", null: false
    t.datetime "hold_expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "idempotency_key"
    t.string "request_fingerprint"
    t.index ["customer_id"], name: "index_reservations_on_customer_id"
    t.index %w[event_id idempotency_key],
            name: "index_reservations_on_event_and_idempotency_key",
            unique: true,
            where: "(idempotency_key IS NOT NULL)"
    t.index ["event_id"], name: "index_reservations_on_event_id"
    t.check_constraint "(upper(seat_range) - lower(seat_range)) <= 6",
                       name: "reservations_seat_group_size"
    t.check_constraint "NOT isempty(seat_range) AND NOT lower_inf(seat_range) AND NOT upper_inf(seat_range)",
                       name: "reservations_seat_range_bounded_and_nonempty"
    t.check_constraint "lower(seat_range) >= 1", name: "reservations_seat_range_starts_positive"
    t.check_constraint "status::text <> 'held'::text OR hold_expires_at IS NOT NULL",
                       name: "reservations_held_requires_hold_expiry"
    t.exclusion_constraint "event_id WITH =, row_id WITH =, seat_range WITH &&",
                           where:
                             "(status)::text = ANY ((ARRAY['held'::character varying, 'confirmed'::character varying])::text[])",
                           using: :gist,
                           name: "reservations_no_active_seat_overlap"
  end

  create_table "stripe_webhook_events", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "event_type", null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_stripe_webhook_events_on_external_id", unique: true
  end

  create_table "venues", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "layout", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "events", "venues"
  add_foreign_key "payments", "reservations"
  add_foreign_key "reservations", "customers"
  add_foreign_key "reservations", "events"
end
