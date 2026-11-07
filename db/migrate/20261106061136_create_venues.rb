class CreateVenues < ActiveRecord::Migration[8.1]
  def change
    create_table :venues do |t|
      t.string :name, null: false
      t.jsonb :layout, null: false

      t.timestamps
    end
  end
end
