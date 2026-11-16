module Api
  module V1
    class CheckoutsController < BaseController
      def create
        if bearer_request?
          return unless require_customer_scope!("reservations:manage")
        else
          return unless require_guest_cookie_origin!
          return unless require_guest_or_customer!
        end

        reservation = find_reservation_for_current_customer(params[:reservation_id])
        return unless authorize_guest_cart_reservation(reservation)
        unless reservation_policy(reservation).checkout?
          render json: {
                   error: {
                     code: "reservation_unavailable",
                     message: "This seat hold is no longer active"
                   }
                 },
                 status: :conflict
          return
        end

        result = Checkouts::CreateStripeSession.call(reservation:)
        response.headers["Cache-Control"] = "no-store"
        render json: {
                 payment_id: result.payment.id,
                 session_id: result.payment.external_id,
                 client_secret: result.client_secret,
                 amount: result.payment.amount,
                 currency: result.payment.currency,
                 status: result.payment.status
               }
      rescue ActiveRecord::RecordNotFound
        render json: {
                 error: {
                   code: "not_found",
                   message: "Reservation not found"
                 }
               },
               status: :not_found
      rescue Checkouts::CreateStripeSession::ProviderUnavailable
        render json: {
                 error: {
                   code: "payment_unavailable",
                   message: "Online payment is temporarily unavailable"
                 }
               },
               status: :service_unavailable
      rescue Checkouts::CreateStripeSession::ReservationUnavailable
        render json: {
                 error: {
                   code: "reservation_unavailable",
                   message: "This seat hold is no longer active"
                 }
               },
               status: :conflict
      rescue Stripe::StripeError => error
        diagnostics =
          %i[http_status code param request_id]
            .filter_map do |attribute|
              "#{attribute}=#{error.public_send(attribute).inspect}" if error.respond_to?(attribute)
            end
            .join(" ")
        Rails.logger.error("Stripe checkout setup failed: class=#{error.class} #{diagnostics}")
        render json: {
                 error: {
                   code: "payment_unavailable",
                   message: "Online payment is temporarily unavailable"
                 }
               },
               status: :service_unavailable
      end

      def show
        if bearer_request?
          return unless require_customer_scope!("reservations:read")
        else
          return unless require_guest_or_customer!
        end

        reservation = find_reservation_for_current_customer(params[:reservation_id])
        return unless authorize_guest_cart_reservation(reservation)

        payment =
          reservation.payments.find_by!(provider_key: "stripe", external_id: params[:session_id])
        render_checkout_status(reservation, payment)
      rescue ActiveRecord::RecordNotFound
        render_checkout_not_found
      end

      def reconcile
        if bearer_request?
          return unless require_customer_scope!("reservations:manage")
        else
          return unless require_guest_cookie_origin!
          return unless require_guest_or_customer!
        end

        config = PaymentProviders::DevelopmentStripe.configuration
        raise Checkouts::CreateStripeSession::ProviderUnavailable unless config.enabled?

        reservation = find_reservation_for_current_customer(params[:reservation_id])
        return unless authorize_guest_cart_reservation(reservation)

        payment =
          reservation.payments.find_by!(provider_key: "stripe", external_id: params[:session_id])
        session =
          Stripe::Checkout::Session.retrieve(payment.external_id, { api_key: config.secret_key })
        Checkouts::ProcessStripeEvent.process_session(
          session:,
          event_id: "reconcile-#{session.id}-#{session.payment_status}",
          event_type: "checkout.session.reconciled"
        )
        reservation.reload
        payment.reload
        render_checkout_status(reservation, payment)
      rescue ActiveRecord::RecordNotFound
        render_checkout_not_found
      rescue Checkouts::CreateStripeSession::ProviderUnavailable
        render json: {
                 error: {
                   code: "payment_unavailable",
                   message: "Payment status is temporarily unavailable"
                 }
               },
               status: :service_unavailable
      end

      private

      def render_checkout_status(reservation, payment)
        response.headers["Cache-Control"] = "no-store"
        render json: {
                 status:
                   reservation.confirmed? ?
                     "succeeded" :
                     payment.status == "failed" ?
                       "failed" :
                       reservation.expired? ? "expired" : "processing",
                 reservation: {
                   id: reservation.id,
                   status: reservation.status
                 }
               }
      end

      def render_checkout_not_found
        render json: {
                 error: {
                   code: "not_found",
                   message: "Checkout session not found"
                 }
               },
               status: :not_found
      end
    end
  end
end
