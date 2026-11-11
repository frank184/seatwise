class AddTicketPriceCentsToEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :ticket_price_cents, :integer, null: false, default: 1_000
    change_column_default :events, :ticket_price_cents, from: 1_000, to: nil
  end

  def down
    remove_column :events, :ticket_price_cents
  end
end
