class Reservation < ApplicationRecord
  STATUSES = %i[held confirmed expired cancelled].freeze
  enum :status, STATUSES.index_with(&:to_s)

  scope :active_for_inventory,
        -> do
          where(status: :confirmed).or(
            where(status: :held).where("hold_expires_at > ?", Time.current)
          )
        end

  belongs_to :event
  belongs_to :customer
  has_many :payments
  validates_presence_of :event, :customer, :status
  validates_presence_of :hold_expires_at, if: :held?
  validates :seat_range, presence: true
  validate :seat_range_must_be_valid

  private

  def seat_range_must_be_valid
    return if seat_range.nil?

    unless seat_range.is_a?(Range) && seat_range.begin.is_a?(Integer) &&
             seat_range.end.is_a?(Integer)
      errors.add(:seat_range, "must have finite integer bounds")
      return
    end

    first_seat = seat_range.begin
    after_last_seat = seat_range.exclude_end? ? seat_range.end : seat_range.end + 1

    errors.add(:seat_range, "must not be empty") if after_last_seat <= first_seat
    errors.add(:seat_range, "must start at seat 1 or later") if first_seat < 1
    errors.add(:seat_range, "must contain no more than 6 seats") if after_last_seat - first_seat > 6
  end
end
