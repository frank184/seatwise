class DispatchPendingTicketDeliveriesJob < ApplicationJob
  queue_as :background

  def perform
    TicketDelivery.pending.find_each do |delivery|
      DeliverTicketEmailJob.perform_later(delivery.id)
    end
  end
end
