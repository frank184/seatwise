require Rails.root.join("lib/oauth_allowed_origins")

allowed_origins = OAuthAllowedOrigins.parse(value: ENV["OAUTH_ALLOWED_ORIGINS"], environment: Rails.env)

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*allowed_origins)
    resource "/oauth/token",
             headers: %w[Accept Authorization Content-Type],
             methods: %i[post options],
             credentials: false,
             max_age: 600
    resource "/oauth/revoke",
             headers: %w[Accept Authorization Content-Type],
             methods: %i[post options],
             credentials: false,
             max_age: 600
    resource "/api/v1/*",
             headers: %w[Accept Authorization Content-Type Idempotency-Key],
             methods: %i[get post delete options],
             credentials: false,
             max_age: 600
  end
end
