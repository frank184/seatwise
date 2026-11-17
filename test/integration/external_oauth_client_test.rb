require "test_helper"

class ExternalOauthClientTest < ActionDispatch::IntegrationTest
  CALLBACK = "https://external-client.example.test/callback"
  ORIGIN = "https://external-client.example.test"
  VERIFIER = "external-development-client-verifier-0123456789"

  setup do
    Doorkeeper::Application.create!(
      name: "Seatwise Portal",
      redirect_uri: "http://www.example.com/oauth/callback",
      scopes: "reservations:read reservations:manage",
      confidential: false,
      secret: nil
    )
    @client =
      Doorkeeper::Application.create!(
        name: "External integration fixture",
        redirect_uri: CALLBACK,
        scopes: "reservations:read reservations:manage",
        confidential: false,
        secret: nil
      )
    sign_in_customer("external-oauth@example.test")
  end

  test "Portal authorization entry and customer reservation page render OAuth client settings" do
    get oauth_start_path, params: { return_to: "/account/reservations?filter=current" }
    assert_response :success
    assert_select "#oauth-client-status[data-controller='portal--oauth'][data-autostart='true']"
    assert_select "#oauth-client-status[data-client-id=?]",
                  Doorkeeper::Application.find_by!(name: "Seatwise Portal").uid
    assert_select "#oauth-client-status[data-redirect-uri=?]", "http://www.example.com/oauth/callback"
    assert_select "#oauth-client-status[data-return-to=?]", "/account/reservations?filter=current"

    get oauth_start_path, params: { return_to: "//attacker.example/collect" }
    assert_response :success
    assert_select "#oauth-client-status[data-return-to=?]", account_reservations_path

    get account_reservations_path
    assert_response :success
    assert_select "main[data-client-id=?]",
                  Doorkeeper::Application.find_by!(name: "Seatwise Portal").uid
    assert_select "main[data-redirect-uri=?]", "http://www.example.com/oauth/callback"
  end

  test "Portal OAuth callback renders the browser exchange inputs" do
    get oauth_callback_path, params: { code: "callback-code", state: "callback-state" }

    assert_response :success
    assert_select "#oauth-client-status[data-controller='portal--oauth']"
    assert_select "#oauth-client-status[data-code='callback-code'][data-state='callback-state']"
    assert_select "#oauth-client-status[data-client-id=?]",
                  Doorkeeper::Application.find_by!(name: "Seatwise Portal").uid
    assert_select "#oauth-client-status[data-redirect-uri='http://www.example.com/oauth/callback']"
  end

  test "external browser uses the shared authorization and token endpoints with PKCE" do
    params = {
      client_id: @client.uid,
      redirect_uri: CALLBACK,
      response_type: "code",
      scope: "reservations:read",
      state: "external-state",
      code_challenge: Digest::SHA256.base64digest(VERIFIER).tr("+", "-").tr("/", "_").delete("="),
      code_challenge_method: "S256"
    }
    get oauth_authorization_path, params: params
    assert_response :success
    assert_includes response.body, @client.name

    post oauth_authorization_path, params: params.merge(commit: "Authorize")
    assert_response :redirect
    callback = URI.parse(response.location)
    assert_equal CALLBACK, "#{callback.scheme}://#{callback.host}#{callback.path}"
    code = Rack::Utils.parse_nested_query(callback.query).fetch("code")

    post oauth_token_path,
         params: {
           grant_type: "authorization_code",
           client_id: @client.uid,
           redirect_uri: "#{CALLBACK}/wrong",
           code:,
           code_verifier: VERIFIER
         },
         headers: {
           "CONTENT_TYPE" => "application/x-www-form-urlencoded"
         }
    assert_response :bad_request

    post oauth_token_path,
         params: {
           grant_type: "authorization_code",
           client_id: @client.uid,
           redirect_uri: CALLBACK,
           code:,
           code_verifier: VERIFIER
         },
         headers: {
           "CONTENT_TYPE" => "application/x-www-form-urlencoded",
           "Origin" => ORIGIN
         }
    assert_response :success
    assert_equal ORIGIN, response.headers.fetch("Access-Control-Allow-Origin")
    assert response.parsed_body.fetch("access_token").present?
  end

  test "only configured external origins receive CORS permission for token and API endpoints" do
    options oauth_token_path,
            headers: {
              "Origin" => ORIGIN,
              "Access-Control-Request-Method" => "POST",
              "Access-Control-Request-Headers" => "authorization,content-type"
            }
    assert_response :success
    assert_equal ORIGIN, response.headers.fetch("Access-Control-Allow-Origin")
    assert_not response.headers.key?("Access-Control-Allow-Credentials")

    options api_v1_reservations_path,
            headers: {
              "Origin" => "https://unlisted.example.test",
              "Access-Control-Request-Method" => "GET",
              "Access-Control-Request-Headers" => "authorization"
            }
    assert_response :success
    assert_not response.headers.key?("Access-Control-Allow-Origin")
    assert_not response.headers.key?("Access-Control-Allow-Credentials")

    options api_v1_reservations_path,
            headers: {
              "Origin" => ORIGIN,
              "Access-Control-Request-Method" => "GET",
              "Access-Control-Request-Headers" => "authorization"
            }
    assert_response :success
    assert_equal ORIGIN, response.headers.fetch("Access-Control-Allow-Origin")
    assert_not response.headers.key?("Access-Control-Allow-Credentials")

    options oauth_revoke_path,
            headers: {
              "Origin" => ORIGIN,
              "Access-Control-Request-Method" => "POST",
              "Access-Control-Request-Headers" => "content-type"
            }
    assert_response :success
    assert_equal ORIGIN, response.headers.fetch("Access-Control-Allow-Origin")
    assert_not response.headers.key?("Access-Control-Allow-Credentials")
  end

  private

  def sign_in_customer(email)
    customer = Customer.find_or_create_by!(email:)
    ActionMailer::Base.deliveries.clear
    get sign_in_path
    post sign_in_code_path, params: { sign_in: { email: customer.email } }
    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
    post verify_sign_in_code_path, params: { sign_in: { code: } }
    assert_response :redirect
  end
end
