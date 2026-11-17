class TicketDelivery < ApplicationRecord
  belongs_to :reservation

  scope :pending, -> { where(delivered_at: nil) }

  validates :reservation_id, uniqueness: true

  after_create_commit :enqueue_delivery

  private

  def enqueue_delivery
    DeliverTicketEmailJob.perform_later(id)
  end
end
