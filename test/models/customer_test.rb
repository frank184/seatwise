require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "requires an email and attempt count" do
    customer = Customer.new
    customer.sign_in_code_attempts = nil

    assert_not customer.valid?
    assert_includes customer.errors[:email], "can't be blank"
    assert_includes customer.errors[:sign_in_code_attempts], "can't be blank"
  end

  test "requires a unique email" do
    customer = Customer.new(email: customers(:one).email, sign_in_code_attempts: 0)

    assert_not customer.valid?
    assert_includes customer.errors[:email], "has already been taken"
  end

  test "database enforces email uniqueness when Rails validation is bypassed" do
    customer = Customer.new(email: customers(:one).email, sign_in_code_attempts: 0)

    assert_raises(ActiveRecord::RecordNotUnique) do
      customer.save!(validate: false)
    end
  end

  test "allows an unverified customer without an active code" do
    customer = Customer.new(email: "new@example.test", sign_in_code_attempts: 0)

    assert_predicate customer, :valid?
    assert_nil customer.email_verified_at
    assert_nil customer.sign_in_code_digest
    assert_nil customer.sign_in_code_expires_at
  end

  test "reaches payments through reservations" do
    assert_equal [ payments(:one) ], customers(:one).payments.to_a
  end
end
