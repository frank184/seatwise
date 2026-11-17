require "test_helper"

module Api
  module V1
    class GuestSessionsControllerTest < ActionDispatch::IntegrationTest
      test "creates a guest with a one-time JSON capability and never sets a cookie" do
        post api_v1_guest_sessions_path, params: {}, as: :json

        assert_response :created
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_nil response.headers["Set-Cookie"]
        token = response.parsed_body.fetch("guest_token")
        assert token.present?
        assert_equal Digest::SHA256.hexdigest(token), Guest.last.secret_digest
      end

      test "ignores incoming cookies because the API has no cookie session" do
        post api_v1_guest_sessions_path,
             params: {},
             headers: { "Cookie" => "guest=not-an-api-credential" },
             as: :json

        assert_response :created
        assert response.parsed_body.fetch("guest_token").present?
        assert_nil response.headers["Set-Cookie"]
      end

      test "does not vary the JSON contract by origin or fetch metadata" do
        post api_v1_guest_sessions_path,
             params: {},
             headers: {
               "Origin" => "https://another-client.example",
               "Sec-Fetch-Site" => "cross-site"
             },
             as: :json

        assert_response :created
        assert response.parsed_body.fetch("guest_token").present?
      end
    end
  end
end
