class ExpireReservationJob < ApplicationJob
  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    Reservations::ExpireIfDue.call(reservation:) if reservation
  end
end
