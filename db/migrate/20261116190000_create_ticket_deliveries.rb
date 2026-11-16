class CreateTicketDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_deliveries do |t|
      t.references :reservation, null: false, foreign_key: true, index: { unique: true }
      t.datetime :delivered_at

      t.timestamps
    end
  end
end
