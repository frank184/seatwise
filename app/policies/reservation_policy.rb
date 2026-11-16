class ReservationPolicy
  def initialize(reservation:, customer: nil, guest_cart: nil)
    @reservation = reservation
    @customer = customer
    @guest_cart = guest_cart
  end

  def show?
    customer_owns_reservation? || guest_cart_owns_reservation?
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

  def guest_cart_owns_reservation?
    @guest_cart.present? && @reservation.guest_cart_id == @guest_cart.id
  end
end
