module OAuthAllowedOrigins
  DEFAULTS = {
    "development" => ["https://oauth-client.example.test", "http://localhost:4000"],
    "test" => ["https://external-client.example.test"]
  }.freeze

  def self.parse(value:, environment:)
    return DEFAULTS.fetch(environment.to_s, []) if value.nil?

    origins = value.split(",").map(&:strip).reject(&:blank?)
    if origins.include?("*")
      raise ArgumentError, "OAUTH_ALLOWED_ORIGINS must not include the wildcard origin '*'."
    end

    origins
  end
end
