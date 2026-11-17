class ReservationPolicy
  def initialize(reservation:, customer: nil, guest: nil)
    @reservation = reservation
    @customer = customer
    @guest = guest
  end

  def show?
    customer_owns_reservation? || guest_owns_reservation?
  end

  def cancel?
    show? && (@reservation.held? || @reservation.cancelled?)
  end

  def checkout?
    show? && @reservation.held?
  end

  private

  def customer_owns_reservation?
    @customer.present? && @reservation.customer_id == @customer.id
  end

  def guest_owns_reservation?
    @guest.present? && @reservation.guest_id == @guest.id
  end
end
