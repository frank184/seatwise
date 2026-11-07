class Payment < ApplicationRecord
  belongs_to :reservation
  delegate :customer, to: :reservation
  validates_presence_of :reservation, :external_id, :status, :amount
end
