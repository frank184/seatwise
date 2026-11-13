class AddStripeCheckoutSupport < ActiveRecord::Migration[8.1]
  def up
    add_column :payments, :provider_key, :string
    add_column :payments, :currency, :string
    add_column :payments, :failure_code, :string

    execute "UPDATE payments SET provider_key = 'simulator', currency = 'cad'"
    execute <<~SQL
      WITH duplicate_pending_payments AS (
        SELECT id, ROW_NUMBER() OVER (
          PARTITION BY reservation_id ORDER BY created_at DESC, id DESC
        ) AS attempt_rank
        FROM payments
        WHERE status = 'pending'
      )
      UPDATE payments
      SET status = 'failed', failure_code = 'superseded_legacy_attempt'
      FROM duplicate_pending_payments
      WHERE payments.id = duplicate_pending_payments.id
        AND duplicate_pending_payments.attempt_rank > 1
    SQL

    change_column_null :payments, :provider_key, false
    change_column_null :payments, :currency, false
    add_index :payments, :external_id, unique: true
    add_index :payments,
              :reservation_id,
              unique: true,
              where: "status = 'pending'",
              name: "index_payments_one_pending_per_reservation"

    create_table :stripe_webhook_events do |t|
      t.string :external_id, null: false
      t.string :event_type, null: false
      t.datetime :processed_at
      t.timestamps
    end
    add_index :stripe_webhook_events, :external_id, unique: true
  end

  def down
    drop_table :stripe_webhook_events
    remove_index :payments, name: "index_payments_one_pending_per_reservation"
    remove_index :payments, :external_id
    remove_column :payments, :failure_code
    remove_column :payments, :currency
    remove_column :payments, :provider_key
  end
end
