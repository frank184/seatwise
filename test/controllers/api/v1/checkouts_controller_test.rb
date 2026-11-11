require "test_helper"

module Api
  module V1
    class CheckoutsControllerTest < ActionDispatch::IntegrationTest
      test "returns session details without returning provider secrets" do
        reservation = Reservation.create!(event: events(:indie_folk), customer: customers(:one), row_id: 9,
          seat_range: 1...3, status: :held, hold_expires_at: 5.minutes.from_now)
        config = PaymentProviders::DevelopmentStripe::Configuration.new(secret_key: "sk_test_secret", publishable_key: "pk_test_public",
          webhook_secret: "whsec_secret", currency: "cad", error: nil)
        with_method_stub(Stripe::Checkout::Session, :create, Struct.new(:id, :client_secret).new("cs_test_endpoint", "cs_secret_public")) do
          with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, config) do
            post api_v1_checkout_session_path(reservation)
          end
        end
        assert_response :success
        assert_equal "cs_secret_public", response.parsed_body.fetch("client_secret")
        assert_equal 2_000, response.parsed_body.fetch("amount")
        assert_not_includes response.body, "sk_test_secret"
        assert_not_includes response.body, "whsec_secret"
      end

      test "returns conflict for an expired hold" do
        reservation = Reservation.create!(event: events(:indie_folk), customer: customers(:one), row_id: 9,
          seat_range: 1...3, status: :held, hold_expires_at: 1.second.ago)
        config = PaymentProviders::DevelopmentStripe::Configuration.new(secret_key: "sk_test_secret", publishable_key: "pk_test_public",
          webhook_secret: nil, currency: "cad", error: nil)
        with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, config) do
          post api_v1_checkout_session_path(reservation)
        end
        assert_response :conflict
        assert reservation.reload.expired?
      end

      test "return reconciliation confirms only the matching server-side Checkout Session" do
        reservation = Reservation.create!(event: events(:indie_folk), customer: customers(:one), row_id: 19,
          seat_range: 1...3, status: :held, hold_expires_at: 5.minutes.from_now)
        payment = reservation.payments.create!(external_id: "cs_test_return", provider_key: "stripe", status: "pending", amount: 2_000, currency: "cad")
        session = Struct.new(:id, :metadata, :amount_total, :currency, :payment_status).new(
          payment.external_id, Struct.new(:reservation_id).new(reservation.id.to_s), payment.amount, payment.currency, "paid"
        )
        config = PaymentProviders::DevelopmentStripe::Configuration.new(secret_key: "sk_test_secret", publishable_key: "pk_test_public",
          webhook_secret: "whsec_secret", currency: "cad", error: nil)

        with_method_stub(Stripe::Checkout::Session, :retrieve, session) do
          with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, config) do
            get api_v1_checkout_status_path(reservation, session_id: payment.external_id)
          end
        end

        assert_response :success
        assert_equal "succeeded", response.parsed_body.fetch("status")
        assert reservation.reload.confirmed?
      end

      private

      def with_method_stub(target, name, value)
        original = target.method(name)
        target.define_singleton_method(name) { |*| value }
        yield
      ensure
        target.define_singleton_method(name, original)
      end
    end
  end
end
