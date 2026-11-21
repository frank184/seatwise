require "application_system_test_case"

module Portal
  class CustomerReservationAccessTest < ApplicationSystemTestCase
    setup { @previous_portal_origin = Rails.application.config.x.portal_origin }

    teardown { Rails.application.config.x.portal_origin = @previous_portal_origin }

    test "customer verifies a delivered OTP before accessing their reservation" do
      visit root_path
      portal_origin = URI.parse(page.current_url).origin
      Rails.application.config.x.portal_origin = portal_origin
      oauth_client =
        Doorkeeper::Application.create!(
          name: "Seatwise Portal",
          redirect_uri: "#{portal_origin}/oauth/callback",
          scopes: "reservations:read reservations:manage",
          confidential: false,
          secret: nil
        )

      reservation = reservations(:two)
      reservation.update!(status: :held, hold_expires_at: 5.minutes.from_now)
      Portal::SignInsController::RATE_LIMIT_STORE.clear
      reservation.customer.update!(
        email: "customer-access-#{SecureRandom.hex(8)}@example.test",
        sign_in_code_digest: nil,
        sign_in_code_expires_at: nil,
        sign_in_code_sent_at: nil,
        sign_in_code_attempts: 0
      )
      ActionMailer::Base.deliveries.clear
      customer, code = Customers::IssueSignInCode.call(email: reservation.customer.email)
      CustomerMailer.sign_in_code(customer, code).deliver_now
      delivered_email = ActionMailer::Base.deliveries.last
      assert delivered_email, "the test should prepare a delivered OTP before browser verification"

      visit account_reservations_path
      assert_selector "form[action='#{sign_in_code_path}']", wait: 10
      fill_in "Email address", with: reservation.customer.email
      click_button "Email me a code"

      code = delivered_email.text_part.body.to_s[/\b\d{6}\b/]
      assert code.present?, "the delivered email should contain the database-backed OTP"
      assert_equal [customer.email], delivered_email.to

      find("input[aria-label='Six-digit verification code']").set(code)

      assert_current_path account_reservations_path, wait: 20
      assert_text(/Reservation #{reservation.id}/i)
      assert_text reservation.event.name
      assert_text "Row 1 · Seat 1"
      assert_selector "[data-reservation-countdown]", text: /\d+:\d{2} remaining/
      assert_selector "[data-reservation-venue-filter] option", text: reservation.event.venue.name
      assert_selector "[data-reservation-status-filter='all'][aria-pressed='true']"
      click_button "On hold"
      assert_current_path account_reservations_path(status: "held"), wait: 10
      assert_text reservation.event.name
      assert oauth_client.persisted?
    end
  end
end
