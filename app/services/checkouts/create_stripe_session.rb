require "digest"

module Checkouts
  class CreateStripeSession
    Result = Data.define(:payment, :client_secret)

    def self.call(reservation:)
      new(reservation:).call
    end

    def initialize(reservation:)
      @reservation = reservation
    end

    def call
      config = PaymentProviders::DevelopmentStripe.configuration
      raise ProviderUnavailable unless config.enabled?

      unavailable = false
      result =
        @reservation.with_lock do
          expire_if_due!
          unless @reservation.held?
            unavailable = true
            next
          end

          payment = @reservation.payments.lock.find_by(status: "pending", provider_key: "stripe")
          return result_for(payment) if payment

          attempt = @reservation.payments.where(provider_key: "stripe").count + 1
          ticket_price_cents = @reservation.event.ticket_price_cents
          amount = @reservation.seat_count * ticket_price_cents
          session_params = {
            ui_mode: "elements",
            mode: "payment",
            allowed_payment_method_types: %w[card link],
            customer_email: @reservation.customer.email,
            line_items: [
              {
                quantity: @reservation.seat_count,
                price_data: {
                  currency: config.currency,
                  unit_amount: ticket_price_cents,
                  product_data: {
                    name: "Event ticket"
                  }
                }
              }
            ],
            metadata: {
              reservation_id: @reservation.id.to_s
            },
            payment_intent_data: {
              metadata: {
                reservation_id: @reservation.id.to_s
              }
            },
            return_url:
              Rails.application.routes.url_helpers.event_url(
                @reservation.event,
                host: default_host,
                reservation_id: @reservation.id,
                session_id: "{CHECKOUT_SESSION_ID}"
              )
          }
          session =
            Stripe::Checkout::Session.create(
              session_params,
              {
                api_key: config.secret_key,
                idempotency_key:
                  "reservation-#{@reservation.id}-checkout-#{attempt}-#{Digest::SHA256.hexdigest(session_params.to_json)}"
              }
            )

          payment =
            @reservation.payments.create!(
              external_id: session.id,
              provider_key: "stripe",
              status: "pending",
              amount: amount,
              currency: config.currency
            )
          Result.new(payment, session.client_secret)
        end
      raise ReservationUnavailable if unavailable

      result
    end

    private

    def result_for(payment)
      config = PaymentProviders::DevelopmentStripe.configuration
      session =
        Stripe::Checkout::Session.retrieve(payment.external_id, { api_key: config.secret_key })
      Result.new(payment, session.client_secret)
    end

    def expire_if_due!
      return unless @reservation.held? && @reservation.hold_expires_at <= Time.current

      @reservation.update!(status: :expired)
    end

    def default_host
      Rails.application.config.action_mailer.default_url_options&.fetch(:host, nil) ||
        "localhost:3000"
    end

    class ProviderUnavailable < StandardError
    end
    class ReservationUnavailable < StandardError
    end
  end
end
