module PaymentProviders
  class DevelopmentStripe
    Configuration =
      Data.define(:secret_key, :publishable_key, :webhook_secret, :currency, :error) do
        def enabled?
          error.nil?
        end
      end

    class << self
      def configuration
        secret_key = setting("STRIPE_SECRET_KEY", :secret_key)
        publishable_key = setting("STRIPE_PUBLISHABLE_KEY", :publishable_key)
        webhook_secret = setting("STRIPE_WEBHOOK_SECRET", :webhook_secret)
        currency = (setting("STRIPE_DEVELOPMENT_CURRENCY", :currency) || "cad").downcase

        error = configuration_error(secret_key, publishable_key, currency)

        Configuration.new(
          secret_key: error ? nil : secret_key,
          publishable_key: error ? nil : publishable_key,
          webhook_secret: webhook_secret,
          currency: currency,
          error: error
        )
      end

      private

      def setting(environment_key, credential_key)
        value = ENV[environment_key]
        value = Rails.application.credentials.dig(:stripe, credential_key) if value.nil? ||
          value.strip.empty?
        value = value.to_s.strip
        value.presence
      end

      def configuration_error(secret_key, publishable_key, currency)
        return "A Stripe test secret key is required." unless test_key?(secret_key, "sk_test_")
        unless test_key?(publishable_key, "pk_test_")
          return "A Stripe test publishable key is required."
        end
        return "Currency must be a three-letter ISO code." unless currency.match?(/\A[a-zA-Z]{3}\z/)

        nil
      end

      def test_key?(value, prefix)
        value&.start_with?(prefix) && value.length > prefix.length
      end
    end
  end
end
