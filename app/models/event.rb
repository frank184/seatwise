class Event < ApplicationRecord
  belongs_to :venue
  has_many :reservations, dependent: :restrict_with_exception
  has_many :active_reservations, -> { active_for_inventory }, class_name: "Reservation"
  validates_presence_of :venue, :name, :start_time, :end_time, :layout_snapshot
  validates :ticket_price_cents, numericality: { only_integer: true, greater_than: 0 }

  def rows
    Array(layout_snapshot&.dig("rows"))
  end

  def rows_with_availability
    reserved_by_row = reserved_seats_by_row
    rows.map do |row|
      row.merge("reserved_seats" => reserved_by_row.fetch(row.fetch("row_id").to_i, []))
    end
  end

  def seat_count
    rows.sum { |row| row.fetch("seat_count", 0).to_i }
  end

  def reserved_seats_by_row
    active_reservations
      .group_by(&:row_id)
      .transform_values do |reservations|
        reservations.flat_map { |reservation| reservation.seat_range.to_a }
      end
  end

  def reserved_count
    active_reservations.sum { |reservation| reservation.seat_range.size }
  end

  def available_count
    [seat_count - reserved_count, 0].max
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name start_time venue_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[venue]
  end

  def self.ransortable_attributes(_auth_object = nil)
    %w[name start_time]
  end
end
