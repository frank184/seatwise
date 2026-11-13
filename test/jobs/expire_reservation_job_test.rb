require "test_helper"

class ExpireReservationJobTest < ActiveJob::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup { travel_to Time.zone.local(2026, 11, 9, 12) }

  teardown { travel_back }

  test "leaves a hold active before its deadline" do
    reservation = held_reservation(expires_at: 1.minute.from_now)

    ExpireReservationJob.perform_now(reservation.id)

    assert reservation.reload.held?
  end

  test "expires a hold at its deadline" do
    reservation = held_reservation(expires_at: Time.current)

    ExpireReservationJob.perform_now(reservation.id)

    assert reservation.reload.expired?
  end

  test "scheduled delivery waits for and expires at the deadline" do
    deadline = 5.minutes.from_now
    reservation = held_reservation(expires_at: deadline)

    assert_enqueued_with(job: ExpireReservationJob, args: [reservation.id], at: deadline) do
      ExpireReservationJob.set(wait_until: deadline).perform_later(reservation.id)
    end

    perform_enqueued_jobs(at: Time.current)
    assert reservation.reload.held?

    travel_to deadline do
      perform_enqueued_jobs(at: deadline)
    end

    assert reservation.reload.expired?
  end

  test "repeated delivery is harmless" do
    reservation = held_reservation(expires_at: Time.current)

    2.times { ExpireReservationJob.perform_now(reservation.id) }

    assert reservation.reload.expired?
  end

  test "cancelled and confirmed reservations and missing ids are safe no-ops" do
    cancelled = reservation_with_status(:cancelled)
    confirmed = reservation_with_status(:confirmed)

    assert_nothing_raised do
      ExpireReservationJob.perform_now(cancelled.id)
      ExpireReservationJob.perform_now(confirmed.id)
      ExpireReservationJob.perform_now(-1)
    end

    assert cancelled.reload.cancelled?
    assert confirmed.reload.confirmed?
  end

  private

  def held_reservation(expires_at:)
    reservation_with_status(:held, hold_expires_at: expires_at)
  end

  def reservation_with_status(status, hold_expires_at: nil)
    Reservation.create!(
      event: events(:indie_folk),
      customer: customers(:one),
      row_id: 42,
      seat_range: 1...2,
      status:,
      hold_expires_at:
    )
  end
end
