class AddSignInCodeSentAtToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :sign_in_code_sent_at, :datetime
  end
end
