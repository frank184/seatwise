class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :email, null: false
      t.index :email, unique: true
      t.datetime :email_verified_at
      t.string :sign_in_code_digest
      t.datetime :sign_in_code_expires_at
      t.integer :sign_in_code_attempts, null: false, default: 0

      t.timestamps
    end
  end
end
