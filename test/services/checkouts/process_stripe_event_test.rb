require "test_helper"

module Checkouts
  class ProcessStripeEventTest < ActiveSupport::TestCase
    include ActiveSupport::Testing::TimeHelpers

    setup do
      travel_to Time.zone.local(2026, 11, 9, 12)
      @reservation = Reservation.create!(event: events(:indie_folk), customer: Customer.create!(email: "webhook@example.test"),
        row_id: 30, seat_range: 1...3, status: :held, hold_expires_at: 5.minutes.from_now)
      @payment = @reservation.payments.create!(external_id: "cs_test_webhook", provider_key: "stripe", status: "pending", amount: 2_000, currency: "cad")
    end

    teardown { travel_back }

    test "confirms a held reservation for a matching paid checkout session" do
      ProcessStripeEvent.call(event: event("evt_paid", "checkout.session.completed", session(payment_status: "paid")))
      assert @reservation.reload.confirmed?
      assert_equal "succeeded", @payment.reload.status
    end

    test "duplicate webhook delivery has no additional effect" do
      payload = event("evt_duplicate", "checkout.session.completed", session(payment_status: "paid"))
      ProcessStripeEvent.call(event: payload)
      ProcessStripeEvent.call(event: payload)
      assert_equal 1, StripeWebhookEvent.where(external_id: "evt_duplicate").count
    end

    test "reconciled unpaid session still expires the hold when a duplicate poll arrives after its deadline" do
      payload = session(payment_status: "unpaid")
      ProcessStripeEvent.process_session(session: payload, event_id: "reconcile-#{payload.id}-unpaid", event_type: "checkout.session.reconciled")

      travel_to @reservation.hold_expires_at + 1.second do
        ProcessStripeEvent.process_session(session: payload, event_id: "reconcile-#{payload.id}-unpaid", event_type: "checkout.session.reconciled")
      end

      assert @reservation.reload.expired?
    end

    test "does not confirm a late success and records follow-up status" do
      @reservation.update!(hold_expires_at: 1.second.ago)
      ProcessStripeEvent.call(event: event("evt_late", "checkout.session.completed", session(payment_status: "paid")))
      assert @reservation.reload.expired?
      assert_equal "late_success", @payment.reload.status
    end

    test "records asynchronous payment failure without confirming reservation" do
      ProcessStripeEvent.call(event: event("evt_failed", "checkout.session.async_payment_failed", session(payment_status: "unpaid")))
      assert @reservation.reload.held?
      assert_equal "failed", @payment.reload.status
    end

    test "does not confirm a session whose metadata does not match reservation" do
      ProcessStripeEvent.call(event: event("evt_mismatch", "checkout.session.completed", session(payment_status: "paid", reservation_id: "wrong")))
      assert @reservation.reload.held?
      assert_equal "failed", @payment.reload.status
    end

    private

    def event(id, type, object)
      Struct.new(:id, :type, :data).new(id, type, Struct.new(:object).new(object))
    end

    def session(payment_status:, reservation_id: @reservation.id)
      Struct.new(:id, :metadata, :amount_total, :currency, :payment_status).new(
        @payment.external_id,
        Struct.new(:reservation_id).new(reservation_id.to_s),
        @payment.amount,
        @payment.currency,
        payment_status
      )
    end
  end
end
