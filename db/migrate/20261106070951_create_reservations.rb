class CreateReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :reservations do |t|
      t.references :event, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.integer :row_id, null: false
      t.int4range :seat_range, null: false
      t.string :status, null: false, default: "held"
      t.datetime :hold_expires_at

      t.timestamps
    end

    add_check_constraint :reservations,
                         "NOT isempty(seat_range) AND NOT lower_inf(seat_range) AND NOT upper_inf(seat_range)",
                         name: "reservations_seat_range_bounded_and_nonempty"

    add_check_constraint :reservations,
                         "lower(seat_range) >= 1",
                         name: "reservations_seat_range_starts_positive"

    add_check_constraint :reservations,
                         "upper(seat_range) - lower(seat_range) <= 6",
                         name: "reservations_seat_group_size"

    add_check_constraint :reservations,
                         "status <> 'held' OR hold_expires_at IS NOT NULL",
                         name: "reservations_held_requires_hold_expiry"

    add_exclusion_constraint :reservations,
                             "event_id WITH =, row_id WITH =, seat_range WITH &&",
                             using: :gist,
                             where: "status IN ('held', 'confirmed')",
                             name: "reservations_no_active_seat_overlap"
  end
end
