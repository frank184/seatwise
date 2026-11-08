require "test_helper"

class ReservationTest < ActiveSupport::TestCase
  test "accepts an inclusive Ruby range of one to six seats" do
    reservation = reservations(:one).dup
    reservation.seat_range = 1..6

    assert_predicate reservation, :valid?
  end

  test "accepts the canonical exclusive upper bound returned by PostgreSQL" do
    reservation = reservations(:one).dup
    reservation.seat_range = 1...7

    assert_predicate reservation, :valid?
  end

  test "requires a seat range" do
    reservation = reservations(:one).dup
    reservation.seat_range = nil

    assert_not reservation.valid?
    assert_includes reservation.errors[:seat_range], "can't be blank"
  end

  test "rejects empty, unbounded, zero-based, and oversized ranges" do
    [1...1, (1..), (-1...2), (1...8)].each do |invalid_range|
      reservation = reservations(:one).dup
      reservation.seat_range = invalid_range

      assert_not reservation.valid?, "expected #{invalid_range.inspect} to be invalid"
    end
  end

  test "requires a hold expiry only while held" do
    reservation = reservations(:one).dup
    reservation.hold_expires_at = nil
    assert_not reservation.valid?
    assert_includes reservation.errors[:hold_expires_at], "can't be blank"

    reservation.status = :confirmed
    assert_predicate reservation, :valid?
  end

  test "rejects statuses outside the Rails enum" do
    assert_raises(ArgumentError) { reservations(:one).status = "unknown" }
  end

  test "database rejects empty ranges when Rails validation is bypassed" do
    reservation = reservations(:one).dup
    reservation.seat_range = 1...1

    assert_raises(ActiveRecord::StatementInvalid) { reservation.save!(validate: false) }
  end

  test "database rejects unbounded ranges when Rails validation is bypassed" do
    reservation = reservations(:one).dup
    reservation.seat_range = (1..)

    assert_raises(ActiveRecord::StatementInvalid) { reservation.save!(validate: false) }
  end

  test "database rejects ranges below seat one when Rails validation is bypassed" do
    reservation = reservations(:one).dup
    reservation.seat_range = -1...2

    assert_raises(ActiveRecord::StatementInvalid) { reservation.save!(validate: false) }
  end

  test "database rejects ranges larger than six seats when Rails validation is bypassed" do
    reservation = reservations(:one).dup
    reservation.seat_range = 1...8

    assert_raises(ActiveRecord::StatementInvalid) { reservation.save!(validate: false) }
  end

  test "database requires a hold expiry for held reservations when Rails validation is bypassed" do
    reservation = reservations(:one).dup
    reservation.hold_expires_at = nil

    assert_raises(ActiveRecord::StatementInvalid) { reservation.save!(validate: false) }
  end

  test "database rejects overlapping active ranges for the same event and row" do
    reservation = reservations(:one).dup
    reservation.seat_range = 1...2
    reservation.status = :confirmed

    assert_raises(ActiveRecord::StatementInvalid) { reservation.save!(validate: false) }
  end

  test "database rejects ranges that share just one seat" do
    existing_reservation = reservations(:one)
    existing_reservation.update!(seat_range: 1...3)

    reservation = existing_reservation.dup
    reservation.seat_range = 2...4

    assert_raises(ActiveRecord::StatementInvalid) { reservation.save!(validate: false) }
  end

  test "a past hold deadline does not stop a held reservation blocking overlap" do
    reservation = reservations(:one).dup
    reservation.seat_range = 1...2
    reservation.hold_expires_at = 1.hour.ago

    assert_raises(ActiveRecord::StatementInvalid) { reservation.save!(validate: false) }
  end

  test "database allows adjacent ranges for the same event and row" do
    reservation = reservations(:one).dup
    reservation.seat_range = 2..3

    assert reservation.save!(validate: false)
    assert_equal 2...4, reservation.reload.seat_range
  end

  test "database allows disjoint ranges with a gap for the same event and row" do
    reservation = reservations(:one).dup
    reservation.seat_range = 3...5

    assert reservation.save!(validate: false)
  end

  test "database allows the same range in a different row" do
    reservation = reservations(:one).dup
    reservation.row_id = 2
    reservation.seat_range = 1...2

    assert reservation.save!(validate: false)
  end

  test "terminal reservations do not block overlapping active ranges" do
    reservation = reservations(:one).dup
    reservation.status = :cancelled
    reservation.seat_range = 1...2

    assert reservation.save!(validate: false)
  end

  test "expired reservations do not block overlapping active ranges" do
    reservation = reservations(:one).dup
    reservation.status = :expired
    reservation.seat_range = 1...2

    assert reservation.save!(validate: false)
  end

  test "active reservations do not conflict with an expired reservation" do
    existing_reservation = reservations(:one)
    existing_reservation.update!(status: :expired)

    reservation = existing_reservation.dup
    reservation.status = :held

    assert reservation.save!(validate: false)
  end

  test "database allows the same range for a different event" do
    reservations(:two).update!(status: :cancelled)

    reservation = reservations(:one).dup
    reservation.event = events(:two)
    reservation.seat_range = 1...2

    assert reservation.save!(validate: false)
  end
end
