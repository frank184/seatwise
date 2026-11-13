require "test_helper"

module Checkouts
  class CreateStripeSessionTest < ActiveSupport::TestCase
    setup do
      @reservation =
        Reservation.create!(
          event: events(:indie_folk),
          customer: Customer.create!(email: "stripe-checkout@example.test"),
          row_id: 9,
          seat_range: 1...4,
          status: :held,
          hold_expires_at: 5.minutes.from_now
        )
      @config =
        PaymentProviders::DevelopmentStripe::Configuration.new(
          secret_key: "sk_test_example",
          publishable_key: "pk_test_example",
          webhook_secret: "whsec_example",
          currency: "cad",
          error: nil
        )
      @stripe_response = Struct.new(:id, :client_secret).new("cs_test_new", "cs_secret_new")
    end

    test "creates one session using server-calculated quantity and persists the pending payment" do
      @reservation.event.update!(ticket_price_cents: 1_500)
      with_method_stub(
        Stripe::Checkout::Session,
        :create,
        ->(params, options) do
          assert_equal "elements", params[:ui_mode]
          assert_equal %w[card link], params[:allowed_payment_method_types]
          assert_equal @reservation.customer.email, params[:customer_email]
          assert_equal 3, params.dig(:line_items, 0, :quantity)
          assert_equal 1_500, params.dig(:line_items, 0, :price_data, :unit_amount)
          assert_equal "sk_test_example", options[:api_key]
          assert_match(
            /\Areservation-#{@reservation.id}-checkout-1-[0-9a-f]{64}\z/,
            options[:idempotency_key]
          )
          @stripe_response
        end
      ) do
        result =
          with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, @config) do
            CreateStripeSession.call(reservation: @reservation)
          end
        assert_equal "cs_secret_new", result.client_secret
        assert_equal 4_500, result.payment.amount
        assert_equal "cad", result.payment.currency
        assert_equal "stripe", result.payment.provider_key
      end
    end

    test "does not create a session when hold has expired" do
      @reservation.update!(hold_expires_at: 1.second.ago)
      with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, @config) do
        assert_raises(CreateStripeSession::ReservationUnavailable) do
          CreateStripeSession.call(reservation: @reservation)
        end
      end
      assert @reservation.reload.expired?
    end

    test "reuses a pending Stripe payment and its Checkout Session" do
      payment =
        @reservation.payments.create!(
          external_id: "cs_test_existing",
          provider_key: "stripe",
          status: "pending",
          amount: 3_000,
          currency: "cad"
        )
      retrieved = Struct.new(:client_secret).new("cs_secret_reused")
      with_method_stub(Stripe::Checkout::Session, :retrieve, retrieved) do
        result =
          with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, @config) do
            CreateStripeSession.call(reservation: @reservation)
          end
        assert_equal payment.id, result.payment.id
        assert_equal "cs_secret_reused", result.client_secret
      end
    end

    test "uses a new Stripe idempotency key after a failed checkout attempt" do
      @reservation.payments.create!(
        external_id: "cs_test_failed",
        provider_key: "stripe",
        status: "failed",
        amount: 3_000,
        currency: "cad"
      )
      with_method_stub(
        Stripe::Checkout::Session,
        :create,
        ->(_params, options) do
          assert_match(
            /\Areservation-#{@reservation.id}-checkout-2-[0-9a-f]{64}\z/,
            options[:idempotency_key]
          )
          @stripe_response
        end
      ) do
        with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, @config) do
          result = CreateStripeSession.call(reservation: @reservation)
          assert_equal "cs_test_new", result.payment.external_id
          assert_equal 2, @reservation.payments.where(provider_key: "stripe").count
        end
      end
    end

    private

    def with_method_stub(target, name, value)
      original = target.method(name)
      target.define_singleton_method(name) do |*args|
        value.respond_to?(:call) ? value.call(*args) : value
      end
      yield
    ensure
      target.define_singleton_method(name, original)
    end
  end
end
