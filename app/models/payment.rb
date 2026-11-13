class Payment < ApplicationRecord
  belongs_to :reservation
  delegate :customer, to: :reservation
  STATUSES = %w[pending succeeded failed late_success refunded].freeze

  validates_presence_of :reservation, :external_id, :status, :amount, :provider_key, :currency
  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, format: { with: /\A[a-z]{3}\z/ }
end
