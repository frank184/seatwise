require "uri"

class TicketMailer < ApplicationMailer
  def confirmation(reservation)
    @reservation = reservation
    @event = reservation.event
    @sign_in_url = sign_in_url

    mail(to: reservation.customer.email, subject: "Your tickets for #{@event.name}")
  end

  private

  def sign_in_url
    sign_in_path = Rails.application.routes.url_helpers.sign_in_path(
      return_to: Rails.application.routes.url_helpers.account_reservations_path
    )
    origin = Rails.application.config.x.portal_origin
    URI.join("#{origin}/", sign_in_path).to_s
  end
end
