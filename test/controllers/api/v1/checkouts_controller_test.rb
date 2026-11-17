require "test_helper"

module Api
  module V1
    class CheckoutsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @guest, @guest_token = Guest.issue!
      end

      test "returns session details without returning provider secrets" do
        reservation =
          Reservation.create!(
            event: events(:indie_folk),
            customer: customers(:one),
            guest: @guest,
            row_id: 9,
            seat_range: 1...3,
            status: :held,
            hold_expires_at: 5.minutes.from_now
          )
        config =
          PaymentProviders::DevelopmentStripe::Configuration.new(
            secret_key: "sk_test_secret",
            publishable_key: "pk_test_public",
            webhook_secret: "whsec_secret",
            currency: "cad",
            error: nil
          )
        with_method_stub(
          Stripe::Checkout::Session,
          :create,
          Struct.new(:id, :client_secret).new("cs_test_endpoint", "cs_secret_public")
        ) do
          with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, config) do
            post api_v1_checkout_session_path(reservation)
          end
        end
        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_equal "cs_secret_public", response.parsed_body.fetch("client_secret")
        assert_equal 2_000, response.parsed_body.fetch("amount")
        assert_not_includes response.body, "sk_test_secret"
        assert_not_includes response.body, "whsec_secret"
      end

      test "returns conflict for an expired hold" do
        reservation =
          Reservation.create!(
            event: events(:indie_folk),
            customer: customers(:one),
            guest: @guest,
            row_id: 9,
            seat_range: 1...3,
            status: :held,
            hold_expires_at: 1.second.ago
          )
        config =
          PaymentProviders::DevelopmentStripe::Configuration.new(
            secret_key: "sk_test_secret",
            publishable_key: "pk_test_public",
            webhook_secret: nil,
            currency: "cad",
            error: nil
          )
        with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, config) do
          post api_v1_checkout_session_path(reservation)
        end
        assert_response :conflict
        assert reservation.reload.expired?
      end

      test "reconcile confirms only the matching server-side Checkout Session" do
        reservation =
          Reservation.create!(
            event: events(:indie_folk),
            customer: customers(:one),
            guest: @guest,
            row_id: 19,
            seat_range: 1...3,
            status: :held,
            hold_expires_at: 5.minutes.from_now
          )
        payment =
          reservation.payments.create!(
            external_id: "cs_test_return",
            provider_key: "stripe",
            status: "pending",
            amount: 2_000,
            currency: "cad"
          )
        session =
          Struct.new(:id, :metadata, :amount_total, :currency, :payment_status).new(
            payment.external_id,
            Struct.new(:reservation_id).new(reservation.id.to_s),
            payment.amount,
            payment.currency,
            "paid"
          )
        config =
          PaymentProviders::DevelopmentStripe::Configuration.new(
            secret_key: "sk_test_secret",
            publishable_key: "pk_test_public",
            webhook_secret: "whsec_secret",
            currency: "cad",
            error: nil
          )

        with_method_stub(Stripe::Checkout::Session, :retrieve, session) do
          with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, config) do
            post api_v1_checkout_reconcile_path(reservation),
                 params: {
                   session_id: payment.external_id
                 }
          end
        end

        assert_response :success
        assert_equal "succeeded", response.parsed_body.fetch("status")
        assert reservation.reload.confirmed?
      end

      test "returns not found when a session does not belong to the reservation" do
        reservation =
          Reservation.create!(
            event: events(:indie_folk),
            customer: customers(:one),
            guest: @guest,
            row_id: 9,
            seat_range: 1...3,
            status: :held,
            hold_expires_at: 5.minutes.from_now
          )
        reservation.payments.create!(
          external_id: "cs_test_owned_session",
          provider_key: "stripe",
          status: "pending",
          amount: 2_000,
          currency: "cad"
        )
        config =
          PaymentProviders::DevelopmentStripe::Configuration.new(
            secret_key: "sk_test_secret",
            publishable_key: "pk_test_public",
            webhook_secret: "whsec_secret",
            currency: "cad",
            error: nil
          )

        with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, config) do
          get api_v1_checkout_status_path(reservation, session_id: "cs_test_other_reservation")
        end

        assert_response :not_found
        assert_equal "not_found", response.parsed_body.dig("error", "code")
      end

      test "cross-origin checkout status GET cannot reconcile or mutate payment state" do
        reservation =
          Reservation.create!(
            event: events(:indie_folk),
            customer: customers(:one),
            guest: @guest,
            row_id: 9,
            seat_range: 1...3,
            status: :held,
            hold_expires_at: 5.minutes.from_now
          )
        payment =
          reservation.payments.create!(
            external_id: "cs_test_cross_origin_read",
            provider_key: "stripe",
            status: "pending",
            amount: 2_000,
            currency: "cad"
          )
        paid_session =
          Struct.new(:id, :metadata, :amount_total, :currency, :payment_status).new(
            payment.external_id,
            Struct.new(:reservation_id).new(reservation.id.to_s),
            payment.amount,
            payment.currency,
            "paid"
          )
        config =
          PaymentProviders::DevelopmentStripe::Configuration.new(
            secret_key: "sk_test_secret",
            publishable_key: "pk_test_public",
            webhook_secret: "whsec_secret",
            currency: "cad",
            error: nil
          )

        with_method_stub(Stripe::Checkout::Session, :retrieve, paid_session) do
          with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, config) do
            get api_v1_checkout_status_path(reservation, session_id: payment.external_id),
                headers: {
                  "Origin" => "https://attacker.example",
                  "Sec-Fetch-Site" => "cross-site"
                }
          end
        end

        assert_response :success
        assert_equal "processing", response.parsed_body.fetch("status")
        assert reservation.reload.held?
        assert_equal "pending", payment.reload.status
      end

      test "checkout reconciliation requires the guest token regardless of origin metadata" do
        reservation =
          Reservation.create!(
            event: events(:indie_folk),
            customer: customers(:one),
            guest: @guest,
            row_id: 9,
            seat_range: 1...3,
            status: :held,
            hold_expires_at: 5.minutes.from_now
          )
        payment =
          reservation.payments.create!(
            external_id: "cs_test_cross_origin_post",
            provider_key: "stripe",
            status: "pending",
            amount: 2_000,
            currency: "cad"
          )
        stripe_retrieved = false
        config =
          PaymentProviders::DevelopmentStripe::Configuration.new(
            secret_key: "sk_test_secret",
            publishable_key: "pk_test_public",
            webhook_secret: "whsec_secret",
            currency: "cad",
            error: nil
          )

        with_method_stub(
          Stripe::Checkout::Session,
          :retrieve,
          replacement: ->(*) do
            stripe_retrieved = true
            raise "unexpected Stripe retrieve"
          end
        ) do
          with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, config) do
            post api_v1_checkout_reconcile_path(reservation),
                 params: {
                   session_id: payment.external_id
                 },
                 headers: {
                   "Authorization" => "",
                   "Origin" => "https://attacker.example",
                   "Sec-Fetch-Site" => "cross-site"
                 }
          end
        end

        assert_response :unauthorized
        assert_not stripe_retrieved
        assert reservation.reload.held?
        assert_equal "pending", payment.reload.status
      end

      test "a different guest cannot create a checkout session for a hold" do
        reservation =
          Reservation.create!(
            event: events(:indie_folk),
            customer: customers(:one),
            guest: @guest,
            row_id: 9,
            seat_range: 1...3,
            status: :held,
            hold_expires_at: 5.minutes.from_now
          )
        post api_v1_guest_sessions_path, params: {}, as: :json
        other_secret = response.parsed_body.fetch("guest_token")

        post api_v1_checkout_session_path(reservation),
             headers: {
               "Authorization" => "Guest #{other_secret}"
             }

        assert_response :not_found
        assert_empty reservation.payments
      end

      test "a customer cannot read or create checkout for another customer's reservation" do
        reservation =
          Reservation.create!(
            event: events(:indie_folk),
            customer: customers(:one),
            guest: @guest,
            row_id: 9,
            seat_range: 1...3,
            status: :held,
            hold_expires_at: 5.minutes.from_now
          )
        token = customer_token(customers(:two), scopes: "reservations:read reservations:manage")
        stripe_called = false

        with_method_stub(
          Stripe::Checkout::Session,
          :create,
          replacement: ->(*) do
            stripe_called = true
            raise "unexpected Stripe create"
          end
        ) { post api_v1_checkout_session_path(reservation), headers: bearer(token) }

        assert_response :not_found
        assert_not stripe_called
        assert_empty reservation.payments
        assert reservation.reload.held?

        get api_v1_checkout_status_path(reservation, session_id: "unknown-session"),
            headers: bearer(token)

        assert_response :not_found
        assert_empty reservation.payments
      end

      test "the owning customer's manage token can create a checkout session" do
        reservation =
          Reservation.create!(
            event: events(:indie_folk),
            customer: customers(:one),
            guest: @guest,
            row_id: 19,
            seat_range: 1...3,
            status: :held,
            hold_expires_at: 5.minutes.from_now
          )
        token = customer_token(customers(:one), scopes: "reservations:manage")
        config =
          PaymentProviders::DevelopmentStripe::Configuration.new(
            secret_key: "sk_test_secret",
            publishable_key: "pk_test_public",
            webhook_secret: "whsec_secret",
            currency: "cad",
            error: nil
          )

        with_method_stub(
          Stripe::Checkout::Session,
          :create,
          Struct.new(:id, :client_secret).new("cs_test_customer_owned", "cs_secret_public")
        ) do
          with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, config) do
            post api_v1_checkout_session_path(reservation), headers: bearer(token)
          end
        end

        assert_response :success
        assert_equal "cs_test_customer_owned", response.parsed_body.fetch("session_id")
        assert_equal 1, reservation.payments.count
      end

      test "a read-only customer token cannot create checkout or payment records" do
        reservation =
          Reservation.create!(
            event: events(:indie_folk),
            customer: customers(:one),
            guest: @guest,
            row_id: 29,
            seat_range: 1...3,
            status: :held,
            hold_expires_at: 5.minutes.from_now
          )
        token = customer_token(customers(:one), scopes: "reservations:read")

        post api_v1_checkout_session_path(reservation), headers: bearer(token)

        assert_response :forbidden
        assert_empty reservation.payments
        assert reservation.reload.held?
      end

      private

      def customer_token(customer, scopes:)
        Doorkeeper::AccessToken.create!(
          application:
            Doorkeeper::Application.create!(
              name: "Checkout API client #{SecureRandom.hex(4)}",
              redirect_uri: "https://client.example.test/callback",
              scopes: "reservations:read reservations:manage",
              confidential: false,
              secret: nil
            ),
          resource_owner: customer,
          scopes:,
          expires_in: 15.minutes.to_i
        )
      end

      def bearer(token)
        { "Authorization" => "Bearer #{token.plaintext_token}" }
      end

      def post(path, **args)
        args[:headers] = { "Authorization" => "Guest #{@guest_token}" }.merge(args[:headers] || {})
        super(path, **args)
      end

      def get(path, **args)
        args[:headers] = { "Authorization" => "Guest #{@guest_token}" }.merge(args[:headers] || {})
        super(path, **args)
      end

      def with_method_stub(target, name, value = nil, replacement: nil)
        original = target.method(name)
        target.define_singleton_method(name, &(replacement || ->(*) { value }))
        yield
      ensure
        target.define_singleton_method(name, original)
      end
    end
  end
end
