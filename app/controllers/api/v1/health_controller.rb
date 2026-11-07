module Api
  module V1
    class HealthController < BaseController
      def show
        render json: { status: "ok", api_version: "v1" }
      end
    end
  end
end
