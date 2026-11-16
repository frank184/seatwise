class CreateGuestCarts < ActiveRecord::Migration[8.1]
  def change
    create_table :guest_carts do |t|
      t.string :secret_digest, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :guest_carts, :secret_digest, unique: true
    add_index :guest_carts, :expires_at
    add_reference :reservations, :guest_cart, foreign_key: { on_delete: :nullify }
  end
end
