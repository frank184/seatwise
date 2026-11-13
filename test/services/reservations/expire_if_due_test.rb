require "test_helper"

module Reservations
  class ExpireIfDueTest < ActiveSupport::TestCase
    include ActiveSupport::Testing::TimeHelpers

    test "expires a hold at its exact deadline" do
      travel_to Time.zone.local(2026, 11, 9, 12)
      reservation =
        Reservation.create!(
          event: events(:indie_folk),
          customer: customers(:one),
          row_id: 40,
          seat_range: 1...2,
          status: :held,
          hold_expires_at: Time.current
        )
      assert_equal reservation, ExpireIfDue.call(reservation:)
      assert reservation.reload.expired?
    ensure
      travel_back
    end

    test "leaves a hold active before its deadline" do
      reservation =
        Reservation.create!(
          event: events(:indie_folk),
          customer: customers(:one),
          row_id: 41,
          seat_range: 1...2,
          status: :held,
          hold_expires_at: 1.minute.from_now
        )
      ExpireIfDue.call(reservation:)
      assert reservation.reload.held?
    end
  end
end
