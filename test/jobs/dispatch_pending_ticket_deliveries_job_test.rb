require "test_helper"

class DispatchPendingTicketDeliveriesJobTest < ActiveJob::TestCase
  test "recurring dispatcher recovers a pending row when initial enqueue failed" do
    reservation = reservations(:three)

    assert_raises(IOError) { with_ticket_enqueue_failure { TicketDelivery.create!(reservation:) } }

    delivery = TicketDelivery.find_by!(reservation:)
    assert_nil delivery.delivered_at
    clear_enqueued_jobs

    assert_enqueued_with(job: DeliverTicketEmailJob, args: [delivery.id]) do
      DispatchPendingTicketDeliveriesJob.perform_now
    end
  end

  test "recurring dispatcher skips delivered rows" do
    delivery = TicketDelivery.create!(reservation: reservations(:three))
    delivery.update!(delivered_at: Time.current)
    clear_enqueued_jobs

    assert_no_enqueued_jobs only: DeliverTicketEmailJob do
      DispatchPendingTicketDeliveriesJob.perform_now
    end
  end

  private

  def with_ticket_enqueue_failure
    original_perform_later = DeliverTicketEmailJob.method(:perform_later)
    DeliverTicketEmailJob.define_singleton_method(:perform_later) do |*|
      raise IOError, "queue unavailable"
    end
    yield
  ensure
    DeliverTicketEmailJob.define_singleton_method(:perform_later, original_perform_later)
  end
end
