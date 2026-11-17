require "test_helper"

class DeliverTicketEmailJobTest < ActiveJob::TestCase
  test "sends the ticket confirmation and marks the delivery complete" do
    delivery = TicketDelivery.create!(reservation: reservations(:three))
    before = ActionMailer::Base.deliveries.size

    DeliverTicketEmailJob.perform_now(delivery.id)

    assert_equal before + 1, ActionMailer::Base.deliveries.size
    assert delivery.reload.delivered_at
  end

  test "leaves delivery pending and retries when mail delivery raises" do
    reservation = reservations(:three)
    delivery = TicketDelivery.create!(reservation:)
    mail = Object.new
    mail.define_singleton_method(:deliver_now) { raise "SMTP unavailable" }

    original_confirmation = TicketMailer.method(:confirmation)
    TicketMailer.define_singleton_method(:confirmation) { |_| mail }

    assert_enqueued_with(job: DeliverTicketEmailJob, args: [delivery.id]) do
      DeliverTicketEmailJob.perform_now(delivery.id)
    end

    assert_nil delivery.reload.delivered_at
  ensure
    if original_confirmation
      TicketMailer.define_singleton_method(:confirmation, original_confirmation)
    end
  end
end
