class DeliverTicketEmailJob < ApplicationJob
  queue_as :mailers

  retry_on StandardError, wait: :polynomially_longer, attempts: 10

  def perform(ticket_delivery_id)
    delivery = TicketDelivery.find_by(id: ticket_delivery_id)
    return unless delivery

    delivery.with_lock do
      delivery.reload
      return if delivery.delivered_at?

      TicketMailer.confirmation(delivery.reservation).deliver_now
      delivery.update!(delivered_at: Time.current)
    end
  end
end
