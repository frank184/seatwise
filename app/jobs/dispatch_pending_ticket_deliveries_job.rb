class DispatchPendingTicketDeliveriesJob < ApplicationJob
  queue_as :background

  def perform
    TicketDelivery.pending.find_each { |delivery| DeliverTicketEmailJob.perform_later(delivery.id) }
  end
end
