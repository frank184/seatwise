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
        guest, guest_token = Guest.issue!
        response.headers["Cache-Control"] = "no-store"
        render json: { guest_token:, expires_at: guest.expires_at.iso8601 }, status: :created
      end
    end
  end
end
