class AddIdempotencyToReservations < ActiveRecord::Migration[8.1]
  def change
    add_column :reservations, :idempotency_key, :string
    add_column :reservations, :request_fingerprint, :string
    add_index :reservations,
              %i[event_id idempotency_key],
              unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "index_reservations_on_event_and_idempotency_key"
  end
end
