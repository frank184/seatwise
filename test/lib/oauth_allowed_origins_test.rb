require "test_helper"

class OAuthAllowedOriginsTest < ActiveSupport::TestCase
  test "rejects wildcard origins" do
    error = assert_raises(ArgumentError) do
      OAuthAllowedOrigins.parse(value: "https://client.example.test, *", environment: "production")
    end

    assert_match(/must not include the wildcard origin/, error.message)
  end

  test "uses explicit origins and environment defaults" do
    assert_equal ["https://client.example.test"],
                 OAuthAllowedOrigins.parse(value: " https://client.example.test ", environment: "production")
    assert_equal ["https://external-client.example.test"],
                 OAuthAllowedOrigins.parse(value: nil, environment: "test")
  end
end
