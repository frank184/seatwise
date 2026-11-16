require "test_helper"
require "digest"

class GuestCartTest < ActiveSupport::TestCase
  test "issues a digest-only capability that resolves to its active cart" do
    cart, secret = GuestCart.issue!(transport: :body)

    assert secret.present?
    assert_equal Digest::SHA256.hexdigest(secret), cart.secret_digest
    assert_not_equal secret, cart.secret_digest
    assert_equal cart, GuestCart.resolve(secret)
    assert_nil GuestCart.resolve("not-the-secret")
    assert_equal 30.days.from_now.to_i, cart.expires_at.to_i
  end

  test "does not resolve an expired cart" do
    cart, secret = GuestCart.issue!(transport: :body)
    cart.update!(expires_at: 1.second.ago)

    assert_nil GuestCart.resolve(secret)
  end

  test "rejects unsupported transports" do
    assert_raises(ArgumentError) { GuestCart.issue!(transport: :portal) }
  end

  test "cleanup removes expired carts without deleting reservations or customers" do
    cart, = GuestCart.issue!(transport: :body)
    reservation =
      Reservation.create!(
        event: events(:indie_folk),
        customer: customers(:one),
        guest_cart: cart,
        row_id: 9,
        seat_range: 1...2,
        status: :held,
        hold_expires_at: 5.minutes.from_now
      )
    cart.update!(expires_at: 1.second.ago)

    assert_difference("Reservation.count", 0) do
      assert_difference("Customer.count", 0) { assert_equal 1, GuestCart.cleanup_expired! }
    end

    assert_not GuestCart.exists?(cart.id)
    assert_nil reservation.reload.guest_cart_id
    assert Customer.exists?(reservation.customer_id)
  end
end
