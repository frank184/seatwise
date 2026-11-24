module Api
  module V1
    class MeController < BaseController
      def show
        return unless require_customer_scope!("reservations:read")

        response.headers["Cache-Control"] = "no-store"
        render json: {
                 data: {
                   id: current_customer.id,
                   email: current_customer.email
                 },
                 meta: {
                   api_version: "v1"
                 }
               }
      end
    end
  end
end
