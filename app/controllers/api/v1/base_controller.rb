module Api
  module V1
    class BaseController < ActionController::API
      protected

      def current_customer
        return @current_customer if defined?(@current_customer)

        token = current_bearer_token
        owner = token.resource_owner if token&.accessible?
        @current_customer = owner.is_a?(Customer) && owner.email_verified_at? ? owner : nil
      end

      def require_customer_scope!(scope)
        token = current_bearer_token
        unless token&.accessible? && current_customer
          render_api_error(
            "unauthorized",
            "A valid customer bearer token is required",
            :unauthorized
          )
          return false
        end
        unless token.scopes.exists?(scope)
          render_api_error("forbidden", "The token does not grant #{scope}", :forbidden)
          return false
        end

        true
      end

      def bearer_request?
        request.authorization.to_s.match?(/\ABearer\s+\S+\z/i)
      end

      def find_reservation_for_current_customer(id)
        current_customer ? current_customer.reservations.find(id) : Reservation.find(id)
      end

      def reservation_policy(reservation)
        ReservationPolicy.new(
          reservation:,
          customer: current_customer,
          guest: current_customer ? nil : current_guest
        )
      end

      def current_guest
        return @current_guest if defined?(@current_guest)

        scheme, token = request.headers["Authorization"].to_s.split(/\s+/, 2)
        @current_guest = Guest.resolve(token) if scheme&.casecmp?("Guest") && token.present?
      end

      def require_guest_or_customer!
        return true if current_customer || current_guest

        render_api_error(
          "unauthorized",
          "A guest or customer credential is required",
          :unauthorized
        )
        false
      end

      def authorize_guest_reservation(reservation)
        if current_customer
          return true if reservation_policy(reservation).show?

          render_api_error("not_found", "Reservation not found", :not_found)
          return false
        end

        guest = current_guest
        unless guest
          render_api_error(
            "unauthorized",
            "A guest or customer credential is required",
            :unauthorized
          )
          return false
        end
        return true if reservation_policy(reservation).show?

        render_api_error("not_found", "Reservation not found", :not_found)
        false
      end

      def render_api_error(code, message, status)
        render json: { error: { code:, message: } }, status:
      end

      private

      def current_bearer_token
        return unless bearer_request?

        @current_bearer_token ||=
          Doorkeeper::OAuth::Token.authenticate(request, :from_bearer_authorization)
      end
    end
  end
end
