# frozen_string_literal: true

module ValidateDoorkeeperAuthorizationClient
  extend ActiveSupport::Concern

  included do
    prepend_before_action :validate_oauth_client_and_redirect_uri, only: %i[new create destroy]
  end

  private

  def validate_oauth_client_and_redirect_uri
    authorization_request =
      Doorkeeper::OAuth::PreAuthorization.new(
        Doorkeeper.configuration,
        send(:pre_auth_params),
        nil
      )
    return render_invalid_oauth_request unless authorization_request.client_valid?

    # Doorkeeper's authorization matcher intentionally ignores loopback ports.
    # This web-client MVP requires exact callback registrations to avoid an
    # unregistered local service receiving an authorization code.
    registered_redirect_uris = authorization_request.client.redirect_uri.to_s.split("\n")
    return render_invalid_oauth_request unless registered_redirect_uris.include?(authorization_request.redirect_uri)

    return unless action_name.in?(%w[new create])

    # Doorkeeper 5.9's force_pkce only requires a challenge for public clients,
    # and accepts any configured challenge method. Require S256 for all clients.
    return if authorization_request.code_challenge.present? && authorization_request.code_challenge_method == "S256"

    render_invalid_oauth_request
  end

  def render_invalid_oauth_request
    render plain: "Invalid OAuth authorization request.", status: :bad_request
  end
end
