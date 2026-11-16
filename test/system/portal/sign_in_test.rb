require "application_system_test_case"

module Portal
  class SignInTest < ApplicationSystemTestCase
    setup do
      Portal::SignInsController::RATE_LIMIT_STORE.clear
      ActionMailer::Base.deliveries.clear
    end

    test "requests a code, verifies the delivered value, and reaches the Portal" do
      visit sign_in_path
      fill_in "Email address", with: "system-buyer@example.test"
      click_button "Email me a code"

      assert_current_path sign_in_verify_path
      code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
      assert code.present?

      find("input[aria-label='Six-digit verification code']").set(code)
      click_button "Verify and continue"

      assert_current_path root_path
      assert_equal "system-buyer@example.test", Customer.find_by!(email: "system-buyer@example.test").email
    end
  end
end
