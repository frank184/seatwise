require "test_helper"

class CustomerMailerTest < ActionMailer::TestCase
  test "the delivered email contains the generated code that verifies successfully" do
    customer, code = Customers::IssueSignInCode.call(email: "buyer@example.test")

    email = CustomerMailer.sign_in_code(customer, code)
    assert_emails 1 do
      email.deliver_now
    end

    delivered = ActionMailer::Base.deliveries.last
    assert_equal [customer.email], delivered.to
    assert_includes delivered.subject, "sign-in code"
    assert_includes delivered.text_part.body.to_s, code
    assert_includes delivered.html_part.body.to_s, code
    assert Customers::VerifySignInCode.call(customer:, code:)
  end

  test "the subject does not contain the one-time code" do
    customer = customers(:one)

    email = CustomerMailer.sign_in_code(customer, "123456")

    assert_equal "Your Seatwise sign-in code", email.subject
    assert_not_includes email.subject, "123456"
  end
end
