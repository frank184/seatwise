require "test_helper"

class OauthPkceTest < ActionDispatch::IntegrationTest
  PORTAL_CALLBACK = "https://portal.example.test/oauth/callback"
  EXTERNAL_CALLBACK = "https://client.example.test/oauth/callback"
  VERIFIER = "seatwise-customer-auth-code-verifier-0123456789"

  setup do
    ActionMailer::Base.deliveries.clear
    @portal_client = create_public_client("Seatwise Portal", PORTAL_CALLBACK)
    @external_client = create_public_client("Seatwise Development OAuth Client", EXTERNAL_CALLBACK)
  end

  test "authorization resumes after OTP and exchanges one hashed S256 code for a short customer token" do
    oauth_params = authorization_params(@portal_client, state: "portal-state")
    get oauth_authorization_path, params: oauth_params
    original_authorization_path = request.fullpath

    assert_equal original_authorization_path,
                 Rack::Utils.parse_nested_query(URI.parse(response.location).query).fetch("return_to")
    follow_redirect!
    assert_response :success

    post sign_in_code_path,
         params: { sign_in: { email: "buyer@example.test" }, return_to: original_authorization_path }
    assert_redirected_to sign_in_verify_path
    follow_redirect!

    delivered_code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
    assert_match(/\A\d{6}\z/, delivered_code)
    post verify_sign_in_code_path, params: { sign_in: { code: delivered_code } }

    assert_redirected_to original_authorization_path
    follow_redirect!

    assert_response :redirect
    callback = URI.parse(response.location)
    callback_params = Rack::Utils.parse_nested_query(callback.query)
    assert_equal PORTAL_CALLBACK, callback.origin + callback.path
    assert_equal "portal-state", callback_params.fetch("state")
    assert callback_params.fetch("code").present?

    grant = Doorkeeper::AccessGrant.by_token(callback_params.fetch("code"))
    assert_not_nil grant
    assert_equal Digest::SHA256.hexdigest(callback_params.fetch("code")), grant.token
    assert_not_equal callback_params.fetch("code"), grant.token
    assert_equal @portal_client.id, grant.application_id
    assert_equal PORTAL_CALLBACK, grant.redirect_uri
    assert_equal "Customer", grant.resource_owner_type
    assert_equal "S256", grant.code_challenge_method
    assert_equal pkce_challenge(VERIFIER), grant.code_challenge

    post oauth_token_path,
         params: token_params(@external_client, callback_params.fetch("code"), code_verifier: VERIFIER),
         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
    assert_response :bad_request

    post oauth_token_path,
         params: token_params(
           @portal_client,
           callback_params.fetch("code"),
           code_verifier: VERIFIER,
           redirect_uri: EXTERNAL_CALLBACK
         ),
         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
    assert_response :bad_request

    post oauth_token_path,
         params: token_params(@portal_client, callback_params.fetch("code"), code_verifier: "wrong-verifier"),
         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body.fetch("error")

    post oauth_token_path,
         params: token_params(@portal_client, callback_params.fetch("code"), code_verifier: VERIFIER),
         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

    assert_response :success
    token_response = response.parsed_body
    assert_equal "Bearer", token_response.fetch("token_type")
    assert_equal 15.minutes.to_i, token_response.fetch("expires_in")
    assert_equal %w[reservations:manage reservations:read], token_response.fetch("scope").split.sort
    assert_not token_response.key?("refresh_token")
    cache_control = response.headers.fetch("Cache-Control").split(",").map(&:strip)
    assert_includes cache_control, "no-store"
    assert_equal "no-cache", response.headers.fetch("Pragma")

    token = Doorkeeper::AccessToken.find_by!(resource_owner_type: "Customer")
    assert_equal Digest::SHA256.hexdigest(token_response.fetch("access_token")), token.token
    assert_not_equal token_response.fetch("access_token"), token.token
    assert_equal Customer.find_by!(email: "buyer@example.test"), token.resource_owner

    post oauth_token_path,
         params: token_params(@portal_client, callback_params.fetch("code"), code_verifier: VERIFIER),
         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
    assert_response :bad_request

    post oauth_revoke_path, params: { client_id: @portal_client.uid, token: token_response.fetch("access_token") }
    assert_response :success
    assert token.reload.revoked?
  end

  test "malformed client and unregistered callback are rejected before the login redirect" do
    valid_params = authorization_params(@portal_client, state: "untrusted-state")
    get oauth_authorization_path, params: valid_params.merge(redirect_uri: "https://attacker.example.test/callback")

    assert_response :bad_request
    assert_nil response.location
    assert_no_match(/attacker\.example\.test|untrusted-state/, response.body)

    get oauth_authorization_path, params: valid_params.merge(client_id: "not-a-client")

    assert_response :bad_request
    assert_nil response.location
    assert_no_match(/untrusted-state/, response.body)
  end

  test "confidential clients still require an S256 challenge before login" do
    confidential_client = Doorkeeper::Application.create!(
      name: "Confidential OAuth Client",
      redirect_uri: EXTERNAL_CALLBACK,
      scopes: "reservations:read",
      confidential: true,
      secret: SecureRandom.hex(32)
    )

    [
      authorization_params(confidential_client, state: "missing-challenge-state").except(:code_challenge),
      authorization_params(confidential_client, state: "missing-method-state").except(:code_challenge_method)
    ].each do |params|
      get oauth_authorization_path, params: params

      assert_response :bad_request
      assert_nil response.location
      assert_no_match(/missing-(?:challenge|method)-state/, response.body)
    end
  end

  test "loopback callback port must exactly match the registered URI before login" do
    loopback_client = create_public_client(
      "Seatwise Portal",
      "http://localhost:3000/oauth/callback"
    )
    params = authorization_params(loopback_client, state: "loopback-state").merge(
      redirect_uri: "http://localhost:3001/oauth/callback"
    )

    get oauth_authorization_path, params: params

    assert_response :bad_request
    assert_nil response.location
    assert_no_match(/localhost:3001|loopback-state/, response.body)
  end

  test "S256 is mandatory and unconfigured scopes are rejected" do
    sign_in_customer("scope-test@example.test")
    plain_params = authorization_params(@portal_client, state: "plain-state").merge(
      code_challenge: VERIFIER,
      code_challenge_method: "plain"
    )

    get oauth_authorization_path, params: plain_params
    assert_response :bad_request
    assert_no_match(/plain-state/, response.body)

    invalid_scope_params = authorization_params(@portal_client, state: "scope-state").merge(scope: "admin")
    get oauth_authorization_path, params: invalid_scope_params
    assert_response :bad_request
    assert_no_match(/scope-state/, response.body)
  end

  test "external development client receives a consent page with its registered identity" do
    sign_in_customer("external-client@example.test")
    params = authorization_params(@external_client, state: "external-state")

    get oauth_authorization_path, params: params

    assert_response :success
    assert_includes response.body, @external_client.name
    assert_includes response.body, "reservations:read"
    assert_includes response.body, "reservations:manage"
    assert_select "form[action='#{oauth_authorization_path}']"
  end

  test "token exchange requires the code verifier" do
    sign_in_customer("missing-verifier@example.test")
    params = authorization_params(@portal_client, state: "missing-verifier-state")
    get oauth_authorization_path, params: params
    assert_response :redirect
    code = Rack::Utils.parse_nested_query(URI.parse(response.location).query).fetch("code")

    post oauth_token_path,
         params: token_params(@portal_client, code),
         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

    assert_response :bad_request
    assert_equal "invalid_request", response.parsed_body.fetch("error")
  end

  test "expired authorization codes cannot be exchanged" do
    sign_in_customer("expired-code@example.test")
    params = authorization_params(@portal_client, state: "expired-code-state")
    get oauth_authorization_path, params: params
    code = Rack::Utils.parse_nested_query(URI.parse(response.location).query).fetch("code")
    grant = Doorkeeper::AccessGrant.by_token(code)
    grant.update!(created_at: 11.minutes.ago)

    post oauth_token_path,
         params: token_params(@portal_client, code, code_verifier: VERIFIER),
         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body.fetch("error")
  end

  private

  def create_public_client(name, redirect_uri)
    Doorkeeper::Application.create!(
      name:,
      redirect_uri:,
      scopes: "reservations:read reservations:manage",
      confidential: false,
      secret: nil
    )
  end

  def authorization_params(client, state:)
    {
      client_id: client.uid,
      redirect_uri: client.redirect_uri,
      response_type: "code",
      scope: "reservations:read reservations:manage",
      state:,
      code_challenge: pkce_challenge(VERIFIER),
      code_challenge_method: "S256"
    }
  end

  def pkce_challenge(verifier)
    Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
  end

  def token_params(client, code, code_verifier: nil, redirect_uri: client.redirect_uri)
    {
      grant_type: "authorization_code",
      client_id: client.uid,
      redirect_uri:,
      code:,
      code_verifier:
    }.compact
  end

  def sign_in_customer(email)
    post sign_in_code_path, params: { sign_in: { email: } }
    assert_redirected_to sign_in_verify_path

    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
    post verify_sign_in_code_path, params: { sign_in: { code: } }
    assert_redirected_to root_path
  end
end
