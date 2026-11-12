require "test_helper"
require "openssl"

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

      test "accepts a valid signed event and delegates it through payment reconciliation" do
        reservation = Reservation.create!(
          event: events(:indie_folk), customer: customers(:one), row_id: 9, seat_range: 1...3,
          status: :held, hold_expires_at: 5.minutes.from_now
        )
        payment = reservation.payments.create!(
          external_id: "cs_test_signed_webhook", provider_key: "stripe", status: "pending", amount: 2_000, currency: "cad"
        )
        payload = JSON.generate(
          id: "evt_signed_webhook",
          object: "event",
          type: "checkout.session.completed",
          data: { object: {
            id: payment.external_id,
            object: "checkout.session",
            metadata: { reservation_id: reservation.id.to_s },
            amount_total: payment.amount,
            currency: payment.currency,
            payment_status: "paid"
          } }
        )
        secret = "whsec_test_value"
        timestamp = Time.now.to_i
        signed_payload = "#{timestamp}.#{payload}"
        signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
        configuration = Struct.new(:enabled?, :webhook_secret).new(true, secret)

        with_configuration(configuration) do
          post api_v1_stripe_webhook_path,
               params: payload,
               headers: {
                 "CONTENT_TYPE" => "application/json",
                 "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
               }
        end

        assert_response :ok
        assert reservation.reload.confirmed?
        assert_equal "succeeded", payment.reload.status
        assert_not_nil StripeWebhookEvent.find_by!(external_id: "evt_signed_webhook").processed_at
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
