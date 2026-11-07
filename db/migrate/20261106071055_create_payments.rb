class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :reservation, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :status, null: false
      t.integer :amount, null: false

      t.timestamps
    end
  end
end
