module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::Cookies

      protected

      # Authentication is added by the OAuth task; guest access stays a separate
      # capability and never derives from Reservation#customer.
      def current_customer
        nil
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

        render_api_error("unauthorized", "A guest-cart or customer credential is required", :unauthorized)
        false
      end

      def authorize_guest_cart_reservation(reservation)
        return true if current_customer&.id == reservation.customer_id

        cart = current_guest_cart
        unless cart
          render_api_error("unauthorized", "A guest-cart or customer credential is required", :unauthorized)
          return false
        end
        return true if reservation.guest_cart_id == cart.id

        render_api_error("not_found", "Reservation not found", :not_found)
        false
      end

      def render_api_error(code, message, status)
        render json: { error: { code:, message: } }, status:
      end
    end
  end
end
