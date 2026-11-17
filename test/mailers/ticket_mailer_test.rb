require "test_helper"

class TicketMailerTest < ActionMailer::TestCase
  test "confirmation includes event, time, seat range, and a sign-in link without reservation authority" do
    reservation = reservations(:two)

    email = TicketMailer.confirmation(reservation)

    assert_equal [reservation.customer.email], email.to
    assert_includes email.subject, reservation.event.name
    assert_includes email.text_part.body.to_s, reservation.event.name
    assert_includes email.html_part.body.to_s, reservation.event.name
    assert_includes email.text_part.body.to_s, "Row #{reservation.row_id}"
    assert_includes email.text_part.body.to_s, "seats 1–1"
    assert_includes email.text_part.body.to_s, reservation.event.start_time.strftime("%B %-d, %Y")
    portal_origin = Rails.application.config.x.portal_origin
    assert_includes email.text_part.body.to_s,
                    "#{portal_origin}/sign-in?return_to=%2Faccount%2Freservations"
    assert_not_includes email.text_part.body.to_s, "reservation_id=#{reservation.id}"
  end
end
