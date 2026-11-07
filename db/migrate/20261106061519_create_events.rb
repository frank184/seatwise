class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :venue, null: false, foreign_key: true
      t.string :name, null: false
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.jsonb :layout_snapshot, null: false

      t.timestamps
    end
  end
end
