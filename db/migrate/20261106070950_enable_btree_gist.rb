class EnableBtreeGist < ActiveRecord::Migration[8.1]
  def change
    # Enables the btree_gist extension, which is required for the exclusion constraint on the reservations table.
    enable_extension "btree_gist"
  end
end
