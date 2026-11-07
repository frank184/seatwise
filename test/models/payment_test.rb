require "test_helper"

class PaymentTest < ActiveSupport::TestCase
  test "requires its reservation, external id, status, and amount" do
    payment = Payment.new

    assert_not payment.valid?
    assert_includes payment.errors[:reservation], "must exist"
    assert_includes payment.errors[:external_id], "can't be blank"
    assert_includes payment.errors[:status], "can't be blank"
    assert_includes payment.errors[:amount], "can't be blank"
  end

  test "delegates customer access through its reservation" do
    assert_equal customers(:one), payments(:one).customer
  end
end
