require "application_system_test_case"

module Portal
  class CustomerReservationAccessTest < ApplicationSystemTestCase
    setup do
      @previous_portal_origin = Rails.application.config.x.portal_origin
    end

    teardown do
      Rails.application.config.x.portal_origin = @previous_portal_origin
    end

    test "customer verifies a delivered OTP before accessing their reservation" do
      visit root_path
      portal_origin = URI.parse(page.current_url).origin
      Rails.application.config.x.portal_origin = portal_origin
      oauth_client = Doorkeeper::Application.create!(
        name: "Seatwise Portal",
        redirect_uri: "#{portal_origin}/oauth/callback",
        scopes: "reservations:read reservations:manage",
        confidential: false,
        secret: nil
      )

      reservation = reservations(:two)
      Portal::SignInsController::RATE_LIMIT_STORE.clear
      reservation.customer.update!(
        email: "customer-access-#{SecureRandom.hex(8)}@example.test",
        sign_in_code_digest: nil,
        sign_in_code_expires_at: nil,
        sign_in_code_sent_at: nil,
        sign_in_code_attempts: 0
      )
      ActionMailer::Base.deliveries.clear
      visit account_reservations_path
      assert_selector "form[action='#{sign_in_code_path}']", wait: 10
      fill_in "Email address", with: reservation.customer.email
      click_button "Email me a code"

      delivered_email = ActionMailer::Base.deliveries.last
      assert delivered_email, "sign-in request should deliver the OTP instead of being throttled"
      code = delivered_email.text_part.body.to_s[/\b\d{6}\b/]
      assert code.present?, "sign-in request should deliver the database-backed OTP"
      assert_equal [reservation.customer.email], delivered_email.to

      find("input[aria-label='Six-digit verification code']").set(code)
      click_button "Verify and continue"

      assert_current_path account_reservations_path, wait: 20
      assert_text "Reservation #{reservation.id}"
      assert_text "row 1, seats 1–1"
      assert oauth_client.persisted?
    end
  end
end
