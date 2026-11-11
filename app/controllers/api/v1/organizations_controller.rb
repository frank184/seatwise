module Api
  module V1
    class OrganizationsController < BaseController
      def show
        return head :not_found unless params[:id] == "development"

        @payment_provider = PaymentProviders::DevelopmentStripe.configuration
        render :show, formats: [:json]
      end
    end
  end
end
