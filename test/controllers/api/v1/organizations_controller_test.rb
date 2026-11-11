require "test_helper"

module Api
  module V1
    class OrganizationsControllerTest < ActionDispatch::IntegrationTest
      PaymentProviderConfiguration = Struct.new(
        :enabled,
        :publishable_key,
        :secret_key,
        :webhook_secret,
        keyword_init: true
      ) do
        def enabled?
          enabled
        end
      end

      test "show returns the enabled development Stripe provider without secrets" do
        configuration = payment_provider_configuration(enabled: true)

        with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, configuration) do
          get "/api/v1/organizations/development"
        end

        assert_response :success
        body = response.parsed_body
        assert_equal(
          {
            "id" => "development",
            "payment_provider" => {
              "id" => "development-stripe",
              "provider_key" => "stripe",
              "enabled" => true,
              "publishable_key" => "pk_test_public"
            }
          },
          body.fetch("data")
        )
        refute_includes response.body, "sk_test_private"
        refute_includes response.body, "whsec_private"
        refute_includes body.fetch("data").fetch("payment_provider").keys,
                        "secret_key"
        refute_includes body.fetch("data").fetch("payment_provider").keys,
                        "webhook_secret"
      end

      test "show disables payment when Stripe credentials are unavailable" do
        configuration = payment_provider_configuration(
          enabled: false,
          publishable_key: nil,
          secret_key: nil,
          webhook_secret: nil
        )

        with_method_stub(PaymentProviders::DevelopmentStripe, :configuration, configuration) do
          get "/api/v1/organizations/development"
        end

        assert_response :success
        assert_equal(
          {
            "id" => "development-stripe",
            "provider_key" => "stripe",
            "enabled" => false,
            "publishable_key" => nil
          },
          response.parsed_body.dig("data", "payment_provider")
        )
      end

      test "show returns not found for an organization other than development" do
        get "/api/v1/organizations/production"

        assert_response :not_found
      end

      private

      def payment_provider_configuration(**attributes)
        PaymentProviderConfiguration.new(
          enabled: true,
          publishable_key: "pk_test_public",
          secret_key: "sk_test_private",
          webhook_secret: "whsec_private",
          **attributes
        )
      end

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
