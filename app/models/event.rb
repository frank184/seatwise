class Event < ApplicationRecord
  belongs_to :venue
  has_many :reservations, dependent: :restrict_with_exception
  validates_presence_of :venue, :name, :start_time, :end_time, :layout_snapshot

  def self.ransackable_attributes(_auth_object = nil)
    %w[name start_time]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[venue]
  end

  def self.ransortable_attributes(_auth_object = nil)
    %w[name start_time]
  end
end
