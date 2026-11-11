module Api
  module V1
    class StripeWebhooksController < BaseController
      def create
        config = PaymentProviders::DevelopmentStripe.configuration
        return head :service_unavailable unless config.enabled? && config.webhook_secret.present?

        event = Stripe::Webhook.construct_event(request.raw_post, request.headers["Stripe-Signature"], config.webhook_secret)
        Checkouts::ProcessStripeEvent.call(event:)
        head :ok
      rescue JSON::ParserError, Stripe::SignatureVerificationError, Stripe::InvalidPayload
        head :bad_request
      end
    end
  end
end
