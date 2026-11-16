require "test_helper"

class DoorkeeperApplicationTest < ActiveSupport::TestCase
  test "public OAuth clients can be stored without a client secret" do
    application =
      Doorkeeper::Application.create!(
        name: "Test Public Client",
        redirect_uri: "https://client.example.test/callback",
        scopes: "reservations:read reservations:manage",
        confidential: false,
        secret: nil
      )

    assert_not application.confidential?
    assert_nil application.secret
    assert_equal "reservations:read reservations:manage", application.scopes.to_s
  end

  test "OAuth client seeds are inert outside development" do
    %w[test production].each do |environment|
      assert_empty DevelopmentOauthClients.seed!(environment:)
      assert_empty Doorkeeper::Application.all
    end
  end

  test "development OAuth client seeding is idempotent and creates no client secrets" do
    first_run = DevelopmentOauthClients.seed!(environment: "development")
    second_run = DevelopmentOauthClients.seed!(environment: "development")

    assert_equal 2, first_run.size
    assert_equal first_run.map(&:id), second_run.map(&:id)
    assert_equal first_run.map(&:uid), second_run.map(&:uid)
    assert_equal ["Seatwise Development OAuth Client", "Seatwise Portal"], first_run.map(&:name).sort
    assert first_run.all? { |application| !application.confidential? && application.secret.nil? }
    assert_equal 2, Doorkeeper::Application.count
  end
end
