require "test_helper"

module Api
  module V1
    class GuestSessionsControllerTest < ActionDispatch::IntegrationTest
      test "cookie transport sets a host-only http-only guest cookie without returning its secret" do
        post api_v1_guest_sessions_path,
             params: {
               transport: "cookie"
             },
             headers: {
               "Origin" => portal_origin
             },
             as: :json

        assert_response :created
        assert_equal "no-store", response.headers["Cache-Control"]
        assert response.headers["Set-Cookie"].include?("guest_cart=")
        assert response.headers["Set-Cookie"].include?("httponly")
        assert response.headers["Set-Cookie"].include?("samesite=lax")
        assert_not_includes response.body, response.cookies.fetch("guest_cart")
        assert_equal 1, GuestCart.count
        assert_equal Digest::SHA256.hexdigest(response.cookies.fetch("guest_cart")),
                     GuestCart.last.secret_digest
      end

      test "body transport returns its capability once and does not set a cookie" do
        post api_v1_guest_sessions_path, params: { transport: "body" }, as: :json

        assert_response :created
        secret = response.parsed_body.fetch("secret")
        assert secret.present?
        assert_equal Digest::SHA256.hexdigest(secret), GuestCart.last.secret_digest
        assert_nil response.headers["Set-Cookie"]
      end

      test "cookie bootstrap rejects a missing or foreign origin" do
        post api_v1_guest_sessions_path, params: { transport: "cookie" }, as: :json
        assert_response :forbidden

        post api_v1_guest_sessions_path,
             params: {
               transport: "cookie"
             },
             headers: {
               "Origin" => "https://attacker.example"
             },
             as: :json
        assert_response :forbidden
        assert_empty GuestCart.all
      end

      test "cookie bootstrap rejects cross-site fetch metadata" do
        post api_v1_guest_sessions_path,
             params: {
               transport: "cookie"
             },
             headers: {
               "Origin" => portal_origin,
               "Sec-Fetch-Site" => "cross-site"
             },
             as: :json

        assert_response :forbidden
        assert_empty GuestCart.all
      end

      private

      def portal_origin
        Rails.application.config.x.portal_origin
      end
    end
  end
end
