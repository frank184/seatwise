require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1000] do |options|
    options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
  end

  setup do
    @previous_portal_origin = Rails.application.config.x.portal_origin
    Capybara.current_session.server.boot
    Rails.application.config.x.portal_origin = Capybara.current_session.server_url
    Portal::SignInsController::RATE_LIMIT_STORE.clear
    ActionMailer::Base.deliveries.clear
  end

  teardown { Rails.application.config.x.portal_origin = @previous_portal_origin }
end
