require "test_helper"

# Chrome 158 no longer accepts the wildcard origin Capybara 3.40 uses when
# clearing browser storage between system tests.
module ClearChromeStorageWithoutWildcardOrigin
  private

  def execute_cdp(command, params = {})
    return super unless command == "Storage.clearDataForOrigin" && params[:origin] == "*"

    storage_types = params[:storageTypes].to_s.split(",")
    super("Network.clearBrowserCookies") if storage_types.delete("cookies")

    origin = Capybara.current_session.server&.base_url
    return unless origin && storage_types.any?

    super(command, params.merge(origin: origin, storageTypes: storage_types.join(",")))
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(ClearChromeStorageWithoutWildcardOrigin)

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
