module Reservations
  class ExpireIfDue
    def self.call(reservation:)
      reservation.with_lock do
        reservation.update!(status: :expired) if reservation.held? && reservation.hold_expires_at <= Time.current
      end
      reservation
    end
  end
end
