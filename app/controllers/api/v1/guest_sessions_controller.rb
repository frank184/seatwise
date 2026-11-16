module Api
  module V1
    class GuestSessionsController < BaseController
      rate_limit to: 20,
                 within: 1.minute,
                 by: -> { request.remote_ip },
                 name: "guest_session_creation",
                 with: -> do
                   render_api_error(
                     "too_many_requests",
                     "Please try again shortly",
                     :too_many_requests
                   )
                 end

      def create
        transport = params[:transport].to_s
        unless GuestCart::TRANSPORTS.include?(transport)
          render_api_error(
            "unprocessable_entity",
            "transport must be cookie or body",
            :unprocessable_entity
          )
          return
        end

        if transport == "cookie"
          return unless require_guest_cookie_origin!(required: true)

          existing_cart = GuestCart.resolve(cookies[:guest_cart])
          return render_cart(existing_cart, status: :ok) if existing_cart
        end

        cart, secret = GuestCart.issue!(transport:)
        if transport == "cookie"
          cookies[:guest_cart] = {
            value: secret,
            expires: cart.expires_at,
            path: "/",
            httponly: true,
            same_site: :lax,
            secure: Rails.env.production?
          }
          render_cart(cart, status: :created)
        else
          response.headers["Cache-Control"] = "no-store"
          render json: { secret:, expires_at: cart.expires_at.iso8601 }, status: :created
        end
      end

      private

      def render_cart(cart, status:)
        response.headers["Cache-Control"] = "no-store"
        render json: { expires_at: cart.expires_at.iso8601 }, status:
      end
    end
  end
end
