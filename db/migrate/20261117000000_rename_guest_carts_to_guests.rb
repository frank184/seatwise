class RenameGuestCartsToGuests < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :reservations, :guest_carts
    rename_table :guest_carts, :guests
    rename_column :reservations, :guest_cart_id, :guest_id
    add_foreign_key :reservations, :guests, column: :guest_id, on_delete: :nullify
  end
end
