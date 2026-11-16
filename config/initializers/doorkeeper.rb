# frozen_string_literal: true

Doorkeeper.configure do
  orm :active_record

  resource_owner_authenticator do
    customer = Customer.find_by(id: session[:customer_id])

    if customer&.email_verified_at?
      customer
    else
      redirect_to sign_in_path(return_to: request.fullpath), status: :see_other
    end
  end

  use_polymorphic_resource_owner
  force_ssl_in_redirect_uri !Rails.env.development? && !Rails.env.test?

  grant_flows %w[authorization_code]
  authorization_code_expires_in 10.minutes
  access_token_expires_in 15.minutes
  force_pkce
  pkce_code_challenge_methods %w[S256]
  default_scopes "reservations:read"
  optional_scopes "reservations:manage"
  enforce_configured_scopes
  enforce_content_type
  hash_token_secrets
  allow_token_introspection false

  skip_authorization { |_resource_owner, client| client.name == "Seatwise Portal" }
end

# Doorkeeper 5.9.9 validates redirect URIs after its resource-owner callback.
# Check the same OAuth request validator first so an invalid callback cannot
# send an unauthenticated browser through OTP or receive an error redirect.
Rails.application.config.to_prepare do
  authorization_controller = Doorkeeper::AuthorizationsController
  unless authorization_controller < ValidateDoorkeeperAuthorizationClient
    authorization_controller.include(ValidateDoorkeeperAuthorizationClient)
  end
end
