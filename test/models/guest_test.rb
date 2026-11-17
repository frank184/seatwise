require "test_helper"
require "digest"

class GuestTest < ActiveSupport::TestCase
  test "issues a digest-only capability that resolves to its active guest" do
    guest, secret = Guest.issue!

    assert secret.present?
    assert_equal Digest::SHA256.hexdigest(secret), guest.secret_digest
    assert_not_equal secret, guest.secret_digest
    assert_equal guest, Guest.resolve(secret)
    assert_nil Guest.resolve("not-the-secret")
    assert_equal 30.days.from_now.to_i, guest.expires_at.to_i
  end

  test "does not resolve an expired guest" do
    guest, secret = Guest.issue!
    guest.update!(expires_at: 1.second.ago)

    assert_nil Guest.resolve(secret)
  end

  test "guest has many reservations" do
    guest, = Guest.issue!
    reservation = build_reservation(guest)
    reservation.save!

    assert_equal [reservation], guest.reservations
  end

  test "cleanup removes expired guests without deleting reservations or customers" do
    guest, = Guest.issue!
    reservation = build_reservation(guest)
    reservation.save!
    guest.update!(expires_at: 1.second.ago)

    assert_difference("Reservation.count", 0) do
      assert_difference("Customer.count", 0) { assert_equal 1, Guest.cleanup_expired! }
    end

    assert_not Guest.exists?(guest.id)
    assert_nil reservation.reload.guest_id
    assert Customer.exists?(reservation.customer_id)
  end

  private

  def build_reservation(guest)
    reservation =
      Reservation.new(
        event: events(:indie_folk),
        customer: customers(:one),
        guest: guest,
        row_id: 9,
        seat_range: 1...2,
        status: :held,
        hold_expires_at: 5.minutes.from_now
      )
  end
end
