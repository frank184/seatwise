require "test_helper"

module Customers
  class IssueSignInCodeTest < ActiveSupport::TestCase
    test "normalizes email and stores only a digest with a ten minute expiry" do
      travel_to Time.zone.parse("2026-11-16 12:00:00") do
        customer, code = Customers::IssueSignInCode.call(email: "  New.Customer@Example.Test ")

        assert_equal "new.customer@example.test", customer.email
        assert_match(/\A\d{6}\z/, code)
        assert_equal OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, code), customer.sign_in_code_digest
        assert_not_equal Digest::SHA256.hexdigest(code), customer.sign_in_code_digest
        assert_not_equal code, customer.sign_in_code_digest
        assert_equal 10.minutes.from_now, customer.sign_in_code_expires_at
        assert_equal Time.current, customer.sign_in_code_sent_at
        assert_equal 0, customer.sign_in_code_attempts
        assert_nil customer.email_verified_at
      end
    end

    test "issues a code for an existing customer and enforces a 60 second resend cooldown" do
      customer = customers(:one)

      Customers::IssueSignInCode.call(email: customer.email)

      assert_raises(Customers::IssueSignInCode::ResendTooSoon) do
        Customers::IssueSignInCode.call(email: customer.email)
      end

      travel 61.seconds do
        assert_nothing_raised { Customers::IssueSignInCode.call(email: customer.email) }
      end
    end

    test "issues a code for an existing verified customer and creates an unverified customer before booking" do
      verified, verified_code = Customers::IssueSignInCode.call(email: customers(:one).email)
      new_customer, new_code = Customers::IssueSignInCode.call(email: "first.booking@example.test")

      assert_match(/\A\d{6}\z/, verified_code)
      assert_match(/\A\d{6}\z/, new_code)
      assert_equal customers(:one).id, verified.id
      assert_not_nil verified.email_verified_at
      assert_nil new_customer.email_verified_at
    end
  end
end
