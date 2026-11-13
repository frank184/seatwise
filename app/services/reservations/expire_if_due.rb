module Reservations
  class ExpireIfDue
    def self.call(reservation:)
      reservation.with_lock do
        if reservation.held? && reservation.hold_expires_at <= Time.current
          reservation.update!(status: :expired)
        end
      end
      reservation
    end
  end
end
