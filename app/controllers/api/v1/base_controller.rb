module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::Cookies

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
          guest_cart: current_customer ? nil : current_guest_cart
        )
      end

      def current_guest_cart
        return @current_guest_cart if defined?(@current_guest_cart)

        authorization = request.headers["Authorization"].to_s
        if authorization.present?
          @guest_cart_credential_source = :authorization
          secret = authorization.delete_prefix("Guest ") if authorization.start_with?("Guest ")
          @current_guest_cart = GuestCart.resolve(secret) if secret.present?
        else
          @guest_cart_credential_source = :cookie
          @current_guest_cart = GuestCart.resolve(cookies[:guest_cart])
        end
      end

      def guest_cookie_credential?
        return false if current_customer || request.headers["Authorization"].present?

        @guest_cart_credential_source != :authorization && cookies[:guest_cart].present?
      end

      def valid_guest_cookie_origin?(required: false)
        return true unless required || guest_cookie_credential?

        origin = request.headers["Origin"]
        fetch_site = request.headers["Sec-Fetch-Site"]
        origin == Rails.application.config.x.portal_origin && fetch_site != "cross-site"
      end

      def require_guest_cookie_origin!(required: false)
        return true if valid_guest_cookie_origin?(required:)

        render_api_error(
          "forbidden",
          "Guest-cookie requests must come from the configured Portal origin",
          :forbidden
        )
        false
      end

      def require_guest_or_customer!
        return true if current_customer || current_guest_cart

        render_api_error(
          "unauthorized",
          "A guest-cart or customer credential is required",
          :unauthorized
        )
        false
      end

      def authorize_guest_cart_reservation(reservation)
        if current_customer
          return true if reservation_policy(reservation).show?

          render_api_error("not_found", "Reservation not found", :not_found)
          return false
        end

        cart = current_guest_cart
        unless cart
          render_api_error(
            "unauthorized",
            "A guest-cart or customer credential is required",
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
