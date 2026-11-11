require "test_helper"

module Api
  module V1
    class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
      test "rejects invalid Stripe signatures" do
        configuration = Struct.new(:enabled?, :webhook_secret).new(true, "whsec_test_value")
        with_configuration(configuration) do
          post api_v1_stripe_webhook_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => "invalid" }
        end
        assert_response :bad_request
      end

      test "returns unavailable when webhook secret is not configured" do
        configuration = Struct.new(:enabled?, :webhook_secret).new(true, nil)
        with_configuration(configuration) do
          post api_v1_stripe_webhook_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
        end
        assert_response :service_unavailable
      end

      private

      def with_configuration(configuration)
        original = PaymentProviders::DevelopmentStripe.method(:configuration)
        PaymentProviders::DevelopmentStripe.define_singleton_method(:configuration) { configuration }
        yield
      ensure
        PaymentProviders::DevelopmentStripe.define_singleton_method(:configuration, original)
      end
    end
  end
end
