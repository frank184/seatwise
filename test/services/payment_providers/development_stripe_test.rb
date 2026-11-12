require "test_helper"

module PaymentProviders
  class DevelopmentStripeTest < ActiveSupport::TestCase
    test "environment variables take precedence over Rails credentials" do
      with_stripe_env(
        "STRIPE_SECRET_KEY" => "sk_test_environment",
        "STRIPE_PUBLISHABLE_KEY" => "pk_test_environment",
        "STRIPE_WEBHOOK_SECRET" => "whsec_environment"
      ) do
        with_credentials(
          secret_key: "sk_test_credentials",
          publishable_key: "pk_test_credentials",
          webhook_secret: "whsec_credentials"
        ) do
          configuration = DevelopmentStripe.configuration

          assert configuration.enabled?
          assert_equal "sk_test_environment", configuration.secret_key
          assert_equal "pk_test_environment", configuration.publishable_key
          assert_equal "whsec_environment", configuration.webhook_secret
        end
      end
    end

    test "development credentials provide a valid sandbox configuration" do
      with_stripe_env do
        with_credentials(
          secret_key: "sk_test_credentials",
          publishable_key: "pk_test_credentials"
        ) do
          configuration = DevelopmentStripe.configuration

          assert configuration.enabled?
          assert_equal "sk_test_credentials", configuration.secret_key
          assert_equal "pk_test_credentials", configuration.publishable_key
          assert_nil configuration.webhook_secret
          assert_equal "cad", configuration.currency
        end
      end
    end

    test "missing credentials return a disabled configuration" do
      with_stripe_env do
        with_credentials({}) do
          configuration = DevelopmentStripe.configuration

          refute configuration.enabled?
          assert_nil configuration.secret_key
          assert_nil configuration.publishable_key
        end
      end
    end

    test "live keys are rejected without exposing their values" do
      with_stripe_env("STRIPE_SECRET_KEY" => "sk_live_do_not_expose") do
        with_credentials(publishable_key: "pk_test_credentials") do
          configuration = DevelopmentStripe.configuration

          refute configuration.enabled?
          assert_nil configuration.secret_key
          refute_includes configuration.error.to_s, "sk_live_do_not_expose"
        end
      end
    end

    test "malformed keys disable configuration" do
      with_stripe_env(
        "STRIPE_SECRET_KEY" => "not-a-test-secret",
        "STRIPE_PUBLISHABLE_KEY" => "pk_test_credentials"
      ) do
        with_credentials({}) do
          configuration = DevelopmentStripe.configuration

          refute configuration.enabled?
          assert_nil configuration.secret_key
        end
      end
    end

    test "a test key prefix without key material is rejected" do
      with_stripe_env("STRIPE_SECRET_KEY" => "sk_test_", "STRIPE_PUBLISHABLE_KEY" => "pk_test_") do
        with_credentials({}) do
          configuration = DevelopmentStripe.configuration

          refute configuration.enabled?
          assert_nil configuration.secret_key
          assert_nil configuration.publishable_key
        end
      end
    end

    test "environment currency overrides credential value" do
      with_stripe_env(
        "STRIPE_SECRET_KEY" => "sk_test_environment",
        "STRIPE_PUBLISHABLE_KEY" => "pk_test_environment",
        "STRIPE_DEVELOPMENT_CURRENCY" => "USD"
      ) do
        with_credentials(
          secret_key: "sk_test_credentials",
          publishable_key: "pk_test_credentials",
          currency: "cad"
        ) do
          configuration = DevelopmentStripe.configuration

          assert configuration.enabled?
          assert_equal "usd", configuration.currency
        end
      end
    end

    private

    def with_stripe_env(values = {})
      keys = %w[
        STRIPE_SECRET_KEY
        STRIPE_PUBLISHABLE_KEY
        STRIPE_WEBHOOK_SECRET
        STRIPE_DEVELOPMENT_CURRENCY
      ]
      previous = keys.to_h { |key| [key, ENV[key]] }
      keys.each { |key| ENV.delete(key) }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    def with_credentials(values)
      application = Rails.application
      original_credentials = application.method(:credentials)
      application.define_singleton_method(:credentials) { { stripe: values } }
      yield
    ensure
      application.define_singleton_method(:credentials, original_credentials)
    end
  end
end
