class Venue < ApplicationRecord
  validates_presence_of :name, :layout

  def self.ransackable_attributes(_auth_object = nil)
    %w[name]
  end
end
