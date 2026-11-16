# frozen_string_literal: true

class DevelopmentOauthClients
  CLIENTS = [
    {
      name: "Seatwise Portal",
      redirect_uri: "http://localhost:3000/oauth/callback"
    },
    {
      name: "Seatwise Development OAuth Client",
      redirect_uri: "https://oauth-client.example.test/callback"
    }
  ].freeze

  def self.seed!(environment: Rails.env)
    return [] unless environment.to_s == "development"

    CLIENTS.map do |attributes|
      application = Doorkeeper::Application.find_or_initialize_by(name: attributes.fetch(:name))
      application.assign_attributes(
        redirect_uri: attributes.fetch(:redirect_uri),
        scopes: "reservations:read reservations:manage",
        confidential: false,
        secret: nil
      )
      application.save! if application.new_record? || application.has_changes_to_save?
      application
    end
  end
end
