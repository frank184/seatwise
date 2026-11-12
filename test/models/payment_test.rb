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

  test "requires a provider key and a three-letter lowercase currency" do
    payment = payments(:one)

    payment.provider_key = nil
    payment.currency = "CAD"

    assert_not payment.valid?
    assert_includes payment.errors[:provider_key], "can't be blank"
    assert_includes payment.errors[:currency], "is invalid"
  end

  test "requires a recognized status and a positive amount" do
    payment = payments(:one)

    payment.status = "processing"
    payment.amount = 0

    assert_not payment.valid?
    assert_includes payment.errors[:status], "is not included in the list"
    assert_includes payment.errors[:amount], "must be greater than 0"
  end

  test "database permits only one pending payment per reservation and one payment per external id" do
    pending_payment = Payment.new(
      reservation: reservations(:one), external_id: "second-pending-payment", provider_key: "stripe",
      status: "pending", amount: 1_000, currency: "cad"
    )
    duplicate_external_id = Payment.new(
      reservation: reservations(:two), external_id: payments(:one).external_id, provider_key: "stripe",
      status: "succeeded", amount: 1_000, currency: "cad"
    )

    assert_raises(ActiveRecord::RecordNotUnique) { pending_payment.save!(validate: false) }
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate_external_id.save!(validate: false) }
  end
end
