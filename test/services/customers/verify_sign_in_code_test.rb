require "test_helper"

module Customers
  class VerifySignInCodeTest < ActiveSupport::TestCase
    test "validates and consumes a code once while verifying the email" do
      customer, code = Customers::IssueSignInCode.call(email: "buyer@example.test")

      assert Customers::VerifySignInCode.call(customer:, code:)

      customer.reload
      assert_not_nil customer.email_verified_at
      assert_nil customer.sign_in_code_digest
      assert_nil customer.sign_in_code_expires_at
      assert_equal 0, customer.sign_in_code_attempts
      assert_not Customers::VerifySignInCode.call(customer:, code:)
    end

    test "rejects malformed and incorrect codes while counting attempts" do
      customer, = Customers::IssueSignInCode.call(email: "buyer@example.test")

      ["", "abc", "12345", "999999"].each do |code|
        assert_not Customers::VerifySignInCode.call(customer:, code:)
      end

      assert_equal 4, customer.reload.sign_in_code_attempts
      assert_nil customer.email_verified_at
    end

    test "exhausts the code after five invalid attempts" do
      customer, = Customers::IssueSignInCode.call(email: "buyer@example.test")

      5.times { assert_not Customers::VerifySignInCode.call(customer:, code: "000000") }

      customer.reload
      assert_equal 5, customer.sign_in_code_attempts
      assert_nil customer.sign_in_code_digest
      assert_nil customer.sign_in_code_expires_at
      assert_nil customer.email_verified_at
    end

    test "clears an expired code and rejects it" do
      customer, code = Customers::IssueSignInCode.call(email: "buyer@example.test")

      travel 10.minutes + 1.second do
        assert_not Customers::VerifySignInCode.call(customer:, code:)
      end

      customer.reload
      assert_nil customer.sign_in_code_digest
      assert_nil customer.sign_in_code_expires_at
      assert_nil customer.email_verified_at
    end

    test "does not verify a customer if the digest is malformed" do
      customer, = Customers::IssueSignInCode.call(email: "buyer@example.test")
      customer.update!(sign_in_code_digest: "not-a-sha256-digest")

      assert_not Customers::VerifySignInCode.call(customer:, code: "123456")
      assert_nil customer.reload.email_verified_at
    end

    test "rejects a plain SHA-256 digest of the correct code" do
      customer, code = Customers::IssueSignInCode.call(email: "buyer@example.test")
      customer.update!(sign_in_code_digest: Digest::SHA256.hexdigest(code))

      assert_not Customers::VerifySignInCode.call(customer:, code:)
      assert_nil customer.reload.email_verified_at
    end
  end
end
