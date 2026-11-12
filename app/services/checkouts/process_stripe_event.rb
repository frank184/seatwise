module Checkouts
  class ProcessStripeEvent
    SUPPORTED_EVENTS = %w[
      checkout.session.completed
      checkout.session.async_payment_succeeded
      checkout.session.async_payment_failed
      checkout.session.reconciled
    ].freeze

    def self.call(event:)
      return unless SUPPORTED_EVENTS.include?(event.type)

      process_session(session: event.data.object, event_id: event.id, event_type: event.type)
    end

    def self.process_session(session:, event_id:, event_type:)
      StripeWebhookEvent.transaction do
        record =
          StripeWebhookEvent.create_or_find_by!(external_id: event_id) do |row|
            row.event_type = event_type
          end

        payment = Payment.find_by!(provider_key: "stripe", external_id: session.id)
        reservation = payment.reservation
        reservation.with_lock do
          Reservations::ExpireIfDue.call(reservation:)
          payment.lock!
          next if record.processed_at

          if session.metadata&.reservation_id.to_s != reservation.id.to_s ||
               session.amount_total.to_i != payment.amount ||
               session.currency.to_s.downcase != payment.currency
            payment.update!(status: "failed", failure_code: "session_mismatch")
          elsif event_type == "checkout.session.async_payment_failed"
            payment.update!(status: "failed", failure_code: "payment_failed")
          elsif session.payment_status == "paid"
            if reservation.confirmed?
              payment.update!(status: "succeeded")
            elsif reservation.held? && reservation.hold_expires_at > Time.current
              reservation.update!(status: :confirmed, hold_expires_at: nil)
              payment.update!(status: "succeeded")
            else
              payment.update!(status: "late_success", failure_code: "hold_expired")
            end
          end
        end
        record.update!(processed_at: Time.current)
      end
    end
  end
end
