class Event < ApplicationRecord
  belongs_to :venue
  validates_presence_of :venue, :name, :start_time, :end_time, :layout_snapshot
end
